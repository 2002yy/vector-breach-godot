// Diagnostic hook for the private Source2Viewer runtime. Source files stay private.
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using ValveResourceFormat;
using ValveResourceFormat.ResourceTypes;
using ValveResourceFormat.TextureDecoders;

public class StartupHook
{
    public static void Initialize()
    {
        try
        {
            var input = Environment.GetEnvironmentVariable("VB_RESOURCE_INPUT");
            var output = Environment.GetEnvironmentVariable("VB_REFLECTION_OUTPUT");
            if (string.IsNullOrEmpty(output) || Directory.Exists(output))
                throw new InvalidDataException("Choose a fresh reflection output directory");
            using var resource = new Resource();
            resource.Read(input);
            var texture = resource.DataBlock as Texture;
            if (texture == null || texture.Format.ToString() != "BC6H" || (int)texture.Flags != 0x50
                || texture.Width != texture.Height || texture.Depth == 0 || texture.NumMipLevels == 0)
                throw new InvalidDataException("Expected square BC6H cubemap array");
            Directory.CreateDirectory(output);
            var mips = new List<object>();
            using (var stream = new FileStream(Path.Combine(output, "reflection.bc6h"), FileMode.CreateNew))
            {
                for (uint mip = 0; mip < texture.NumMipLevels; mip++)
                {
                    var size = Math.Max(1, texture.Width >> (int)mip);
                    var faceBytes = Math.Max(1, (size + 3) / 4) * Math.Max(1, (size + 3) / 4) * 16;
                    var buffer = new byte[texture.CalculateBufferSizeForMipLevel(mip)];
                    if (buffer.Length != faceBytes * texture.Depth * 6)
                        throw new InvalidDataException("Unexpected mip packing");
                    texture.ReadTextureMipLevel(buffer.AsSpan(), mip);
                    mips.Add(new { level = mip, size, offset = stream.Position, face_bytes = faceBytes,
                        bytes = buffer.Length, sha256 = Convert.ToHexString(SHA256.HashData(buffer)).ToLowerInvariant() });
                    stream.Write(buffer);
                }
            }
            var samples = new List<object>();
            foreach (uint index in new uint[] { 0, (uint)texture.Depth / 2, (uint)texture.Depth - 1 })
                for (uint mip = 0; mip < texture.NumMipLevels; mip++)
                    for (int face = 0; face < 6; face++)
                    {
                        using var bitmap = texture.GenerateBitmap(index, (Texture.CubemapFace)face, mip, TextureCodec.None);
                        if (bitmap.ColorType != SkiaSharp.SKColorType.RgbaF32 || bitmap.RowBytes != bitmap.Width * 16)
                            throw new InvalidDataException("Expected linear HDR float CPU reference");
                        var pixels = MemoryMarshal.Cast<byte, float>(bitmap.GetPixelSpan());
                        foreach (var fraction in new (float x, float y)[] { (.5f,.5f),(.23f,.37f),(.71f,.59f),(.13f,.83f),(.87f,.19f) })
                        {
                            int x = (int)(fraction.x * bitmap.Width), y = (int)(fraction.y * bitmap.Height);
                            int at = (y * bitmap.Width + x) * 4;
                            var rgb = new float[] { pixels[at], pixels[at + 1], pixels[at + 2] };
                            foreach (float value in rgb)
                                if (!float.IsFinite(value) || value < 0)
                                    throw new InvalidDataException("Invalid BC6H unsigned reference pixel");
                            samples.Add(new { index, mip, face, x, y, size = bitmap.Width, rgb });
                        }
                    }
            var data = new { schema = 1, contract = "source-reflection-blocks-v1", width = texture.Width,
                cubes = texture.Depth, mip_count = texture.NumMipLevels, format = "BC6H-UFLOAT",
                layout = "mip-ascending/cube/face/BC6H-blocks", face_order = new[] { "+X", "-X", "+Y", "-Y", "+Z", "-Z" },
                file = "reflection.bc6h", mips, samples };
            Console.WriteLine(JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true }));
            Environment.Exit(0);
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error);
            Environment.Exit(2);
        }
    }
}
