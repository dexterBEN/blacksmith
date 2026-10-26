namespace Blacksmith.Application.Exceptions;

public sealed class ResourceConflictException(string code, string message, int status = 409) : Exception(message)
{
    public string Code { get; } = code;
    public int Status { get; } = status;
}
