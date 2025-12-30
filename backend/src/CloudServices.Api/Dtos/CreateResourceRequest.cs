namespace CloudServices.Api.Dtos;

public sealed class CreateResourceRequest
{
    public string Name { get; set; } = string.Empty;
    public int X { get; set; }
    public int Y { get; set; }

    public string Type { get; set; } = string.Empty;
}