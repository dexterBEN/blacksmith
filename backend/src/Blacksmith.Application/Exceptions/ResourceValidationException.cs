namespace Blacksmith.Application.Exceptions;

public sealed class ResourceValidationException : Exception
{
    public ResourceValidationException(string message) : base(message) { }
}
