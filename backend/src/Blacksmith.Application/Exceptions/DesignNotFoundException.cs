namespace Blacksmith.Application.Exceptions;

public sealed class DesignNotFoundException(Guid designId, Exception? innerException = null)
    : Exception("Design not found.", innerException)
{
    public Guid DesignId { get; } = designId;
}
