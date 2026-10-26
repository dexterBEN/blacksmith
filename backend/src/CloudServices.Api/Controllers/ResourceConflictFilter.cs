using Blacksmith.Application.Exceptions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace CloudServices.Api.Controllers;

public sealed class ResourceConflictFilterAttribute : ExceptionFilterAttribute
{
    public override void OnException(ExceptionContext context)
    {
        if (context.Exception is not ResourceConflictException error) return;
        context.Result = new ObjectResult(new { code = error.Code, error = error.Message }) { StatusCode = error.Status };
        context.ExceptionHandled = true;
    }
}
