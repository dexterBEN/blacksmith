namespace Blacksmith.Application.Exceptions;

public sealed class ConfigurationPayloadTooLargeException : Exception
{
    public ConfigurationPayloadTooLargeException() : base("Configuration request exceeds the 16384-byte limit.") { }
}

public sealed class StoredConfigurationUnsupportedException : Exception
{
    public StoredConfigurationUnsupportedException() : base("Stored configuration is not supported by this API. Replace it with a complete supported document.") { }
}
