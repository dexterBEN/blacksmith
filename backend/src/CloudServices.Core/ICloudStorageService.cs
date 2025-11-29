
namespace CloudServices.Core;

public interface ICloudStorageService
{
    /// <summary>
    /// Crée un bucket dans le projet donné.
    /// Retourne le nom du bucket créé.
    /// </summary>
    Task<string> CreateBucketAsync(string projectId, string bucketName);
}