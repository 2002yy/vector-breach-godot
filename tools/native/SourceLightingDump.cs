// Diagnostic startup hook for the locally installed Source2Viewer 20.1 runtime.
// Compile against its extracted assemblies; no native assets are redistributed.
using System;
using System.IO;
using System.Linq;
using System.Text.Json;
using ValveKeyValue;
using ValveResourceFormat;
using ValveResourceFormat.ResourceTypes;

public class StartupHook
{
    private static object Normalize(KVObject value)
    {
        if (value.IsNull) return null;
        if (value.IsArray) return value.Values.Select(Normalize).ToArray();
        if (value.IsCollection) return value.ToDictionary(pair => pair.Key, pair => Normalize(pair.Value));
        return value.ValueType switch
        {
            KVValueType.String => (string)value,
            KVValueType.Boolean => (bool)value,
            KVValueType.BinaryBlob => Convert.ToBase64String((byte[])value),
            KVValueType.UInt64 => (ulong)value,
            KVValueType.UInt32 => (uint)value,
            KVValueType.UInt16 => (ushort)value,
            KVValueType.Int64 => (long)value,
            KVValueType.Int32 => (int)value,
            KVValueType.Int16 => (short)value,
            KVValueType.FloatingPoint => (float)value,
            KVValueType.FloatingPoint64 => (double)value,
            _ => throw new InvalidDataException("Unsupported KV type: " + value.ValueType),
        };
    }

    private static object DecodeTexture(Texture texture)
    {
        var output = Environment.GetEnvironmentVariable("VB_RESOURCE_RGBA");
        if (string.IsNullOrEmpty(output)) return new {
            dimensions = new int[] { texture.Width, texture.Height, texture.Depth },
            format = texture.Format.ToString(), flags = (int)texture.Flags,
        };
        if (!BitConverter.IsLittleEndian || ((int)texture.Flags & 0x20) == 0
            || texture.Depth < 6 || texture.Depth % 6 != 0 || !texture.IsHighDynamicRange)
            throw new InvalidDataException("Expected six-face HDR probe volume");
        using var stream = new FileStream(output, FileMode.CreateNew, FileAccess.Write);
        for (uint z = 0; z < texture.Depth; z++)
        {
            using var bitmap = texture.GenerateBitmap(z);
            if (bitmap.ColorType != SkiaSharp.SKColorType.RgbaF32 || bitmap.RowBytes != texture.Width * 16)
                throw new InvalidDataException("Unexpected decoded float pixel layout");
            stream.Write(bitmap.GetPixelSpan());
        }
        return new {
            dimensions = new int[] { texture.Width, texture.Height, texture.Depth },
            format = texture.Format.ToString(), flags = (int)texture.Flags,
            layout = "zyx-rgba-f32-le", byte_length = stream.Length,
            decode = "VRF GenerateBitmap HDR; no LDR conversion or gamma transform",
        };
    }

    public static void Initialize()
    {
        try
        {
            using var resource = new Resource();
            resource.Read(Environment.GetEnvironmentVariable("VB_RESOURCE_INPUT"));
            object data;
            if (resource.DataBlock is EntityLump entities)
                data = new { entities = entities.GetEntities().Select(entity => Normalize(entity)).ToArray(),
                    children = entities.GetChildEntityNames() };
            else if (resource.DataBlock is Texture texture)
                data = DecodeTexture(texture);
            else
                data = Normalize((KVObject)resource.DataBlock.GetType().GetProperty("Data").GetValue(resource.DataBlock));
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
