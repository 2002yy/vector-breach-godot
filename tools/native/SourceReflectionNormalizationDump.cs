using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text.Json;
using ValveResourceFormat;
using ValveResourceFormat.ResourceTypes;

public class StartupHook
{
    public static void Initialize()
    {
        try
        {
            using var resource = new Resource();
            resource.Read(Environment.GetEnvironmentVariable("VB_RESOURCE_INPUT"));
            var texture = resource.DataBlock as Texture;
            if (texture == null) throw new InvalidDataException("Expected texture");
            var output = Environment.GetEnvironmentVariable("VB_NORMALIZATION_OUTPUT");
            if (string.IsNullOrEmpty(output) || Directory.Exists(output))
                throw new InvalidDataException("Choose a fresh output directory");
            Directory.CreateDirectory(output);
            object result;
            if (Environment.GetEnvironmentVariable("VB_NORMALIZATION_KIND") == "sh")
            {
                var entries = texture.ExtraData.Where(p => p.Key.ToString() == "CUBEMAP_RADIANCE_SH").ToArray();
                if (entries.Length != 1) throw new InvalidDataException("Missing original radiance SH");
                var raw = entries[0].Value;
                using var reader = new BinaryReader(new MemoryStream(raw));
                var offset = reader.ReadUInt32();
                var count = reader.ReadUInt32();
                if (count != texture.Depth * 27 || offset != 8 || raw.Length != 8)
                    throw new InvalidDataException($"Unexpected original SH layout depth={texture.Depth} count={count} offset={offset} length={raw.Length}");
                // These VTEX files declare an 8-byte extra header; the coefficient
                // payload follows outside that declared size. Use VRF's parsed array.
                var coefficients = typeof(Texture).GetProperty("RadianceCoefficients")?.GetValue(texture) as float[];
                if (coefficients == null || coefficients.Length != count)
                    throw new InvalidDataException("VRF did not parse original radiance coefficients");
                for (int i = 0; i < count; i++)
                {
                    if (!float.IsFinite(coefficients[i])) throw new InvalidDataException("Nonfinite SH");
                }
                using (var writer = new BinaryWriter(File.Create(Path.Combine(output,"radiance-sh-f32.bin"))))
                    foreach (float coefficient in coefficients) writer.Write(coefficient);
                File.WriteAllBytes(Path.Combine(output,"radiance-sh-extra.bin"),raw);
                result = new { cubes = texture.Depth, native_coefficients = coefficients,
                    compiled_sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(Environment.GetEnvironmentVariable("VB_RESOURCE_INPUT")))).ToLowerInvariant(),
                    extra_sha256 = Convert.ToHexString(SHA256.HashData(raw)).ToLowerInvariant() };
            }
            else
            {
                if (texture.Width != 64 || texture.Height != 64 || texture.Depth != 3
                    || texture.Format.ToString() != "RGBA16161616F" || texture.NumMipLevels != 1)
                    throw new InvalidDataException($"Unknown BRDF {texture.Width}x{texture.Height}x{texture.Depth} {texture.Format} mips={texture.NumMipLevels}");
                var raw = new byte[texture.CalculateBufferSizeForMipLevel(0)];
                texture.ReadTextureMipLevel(raw.AsSpan(),0);
                if (raw.Length != 64*64*3*8) throw new InvalidDataException("BRDF byte count");
                using var writer = new BinaryWriter(File.Create(Path.Combine(output,"brdf-rgba-f32.bin")));
                for (int at=0; at<raw.Length; at+=2)
                {
                    float value = (float)BitConverter.UInt16BitsToHalf(BitConverter.ToUInt16(raw,at));
                    if (!float.IsFinite(value)) throw new InvalidDataException("Nonfinite BRDF");
                    writer.Write(value);
                }
                File.WriteAllBytes(Path.Combine(output,"brdf-native-f16.bin"),raw);
                result = new { width=64, height=64, layers=3, format="RGBA-F32-LE", layout="layer/y/x/rgba",
                    native_sha256=Convert.ToHexString(SHA256.HashData(raw)).ToLowerInvariant() };
            }
            Console.WriteLine(JsonSerializer.Serialize(result));
            Environment.Exit(0);
        }
        catch (Exception error) { Console.Error.WriteLine(error); Environment.Exit(2); }
    }
}
