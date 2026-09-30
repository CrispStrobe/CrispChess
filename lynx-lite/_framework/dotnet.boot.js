export const config = /*json-start*/{
  "mainAssemblyName": "Lynx.Wasm.dll",
  "resources": {
    "hash": "sha256-HslasDE7m0jpEOoVt7NORji4n1c2nqe4L2BDzdiKcDs=",
    "jsModuleNative": [
      {
        "name": "dotnet.native.js"
      }
    ],
    "jsModuleRuntime": [
      {
        "name": "dotnet.runtime.js"
      }
    ],
    "wasmNative": [
      {
        "name": "dotnet.native.wasm",
        "hash": "sha256-QrMX9w/n1mTPpr9aIHi62MblNguK0rZ4GGA1zLz0ul0="
      }
    ],
    "wasmSymbols": [
      {
        "name": "dotnet.native.js.symbols"
      }
    ],
    "coreAssembly": [
      {
        "virtualPath": "System.Private.CoreLib.wasm",
        "name": "System.Private.CoreLib.wasm",
        "hash": "sha256-/f0IPMc9yOZh6xf9AMKpBLQz8migtfEG+QTXdg+ASnc="
      },
      {
        "virtualPath": "System.Runtime.InteropServices.JavaScript.wasm",
        "name": "System.Runtime.InteropServices.JavaScript.wasm",
        "hash": "sha256-tYkewVP01o3TwMnjuAaeAtpjZsrlfIAZvgEZsfQ/iYU="
      }
    ],
    "assembly": [
      {
        "virtualPath": "Lynx.wasm",
        "name": "Lynx.wasm",
        "hash": "sha256-xCNttM0NITphFiKthJrZkfvXVwUB13Zmu7ZEWK4zzaA="
      },
      {
        "virtualPath": "Lynx.Wasm.wasm",
        "name": "Lynx.Wasm.wasm",
        "hash": "sha256-kIFNrLtC77Xi9e3olp6fQteb9liOaDR+C2qVIhJxlZc="
      },
      {
        "virtualPath": "Microsoft.Extensions.Configuration.Abstractions.wasm",
        "name": "Microsoft.Extensions.Configuration.Abstractions.wasm",
        "hash": "sha256-ti7twtspTnEIvy7b2wp42P04b6pT3WT5Yww+fyLV6hM="
      },
      {
        "virtualPath": "Microsoft.Extensions.Configuration.Binder.wasm",
        "name": "Microsoft.Extensions.Configuration.Binder.wasm",
        "hash": "sha256-EX2nOdsLa5KEoRJMytB4gOslk9O988h0GRygW4OooWg="
      },
      {
        "virtualPath": "Microsoft.Extensions.Configuration.wasm",
        "name": "Microsoft.Extensions.Configuration.wasm",
        "hash": "sha256-FtGbbGA+eoaD5fHy12dN41XvRyDr8ZU0BvzsQSC/tgk="
      },
      {
        "virtualPath": "Microsoft.Extensions.Configuration.EnvironmentVariables.wasm",
        "name": "Microsoft.Extensions.Configuration.EnvironmentVariables.wasm",
        "hash": "sha256-o7em1BGjxEPALCalkuH0lIHzr5Z4RMsBpNw/k/L1KMg="
      },
      {
        "virtualPath": "Microsoft.Extensions.Configuration.FileExtensions.wasm",
        "name": "Microsoft.Extensions.Configuration.FileExtensions.wasm",
        "hash": "sha256-7ZvmhziC0HBNnTsuIoGT9d0w/aBZ8sscCcQm0Chn1W4="
      },
      {
        "virtualPath": "Microsoft.Extensions.Configuration.Json.wasm",
        "name": "Microsoft.Extensions.Configuration.Json.wasm",
        "hash": "sha256-oFdJLierZGswKwpVsVuq+8+QGBEMyDBnYfdoJl+Dw8Y="
      },
      {
        "virtualPath": "Microsoft.Extensions.FileProviders.Abstractions.wasm",
        "name": "Microsoft.Extensions.FileProviders.Abstractions.wasm",
        "hash": "sha256-jRWGLIs9VnBxaFIMm3+s5YDN6ZeAGGykxPbOmaku8C8="
      },
      {
        "virtualPath": "Microsoft.Extensions.FileProviders.Physical.wasm",
        "name": "Microsoft.Extensions.FileProviders.Physical.wasm",
        "hash": "sha256-URjOsdSmOQRFWMqsRgeT3d2VYePqVW9iWedBDTPdIQE="
      },
      {
        "virtualPath": "Microsoft.Extensions.FileSystemGlobbing.wasm",
        "name": "Microsoft.Extensions.FileSystemGlobbing.wasm",
        "hash": "sha256-VQzKDERjKCTuNPysYzgt4Cdx+fYWplWSFd3ZcywgEK8="
      },
      {
        "virtualPath": "Microsoft.Extensions.ObjectPool.wasm",
        "name": "Microsoft.Extensions.ObjectPool.wasm",
        "hash": "sha256-UdHNAY5/HdkJTjpsODLOdHDEm9gTNwkOrhhZZ5ZpVEE="
      },
      {
        "virtualPath": "Microsoft.Extensions.Primitives.wasm",
        "name": "Microsoft.Extensions.Primitives.wasm",
        "hash": "sha256-muFHleJB/87EBt5M1qjThgF0BlY7IthL3JZcRrt6x+I="
      },
      {
        "virtualPath": "NLog.wasm",
        "name": "NLog.wasm",
        "hash": "sha256-vx0wYURl9r7+acFELmTjtwtqPdV9r61gnJ5C0fLMlQE="
      },
      {
        "virtualPath": "System.Collections.Concurrent.wasm",
        "name": "System.Collections.Concurrent.wasm",
        "hash": "sha256-yrsRa+jovSAt6Vf43sc0+0bkLkPVABfBJfEFtSgcR7w="
      },
      {
        "virtualPath": "System.Collections.wasm",
        "name": "System.Collections.wasm",
        "hash": "sha256-vYVi7HWPhW4++UeF0H2OuwdcS7Gih3GYnzp3k3bYblU="
      },
      {
        "virtualPath": "System.Collections.Immutable.wasm",
        "name": "System.Collections.Immutable.wasm",
        "hash": "sha256-fe7FRMAPKlhOMSDVXCDVXghnQMDxEw66tDT1Bn+FgU8="
      },
      {
        "virtualPath": "System.Collections.NonGeneric.wasm",
        "name": "System.Collections.NonGeneric.wasm",
        "hash": "sha256-UIX6/xHVOMi6OqxFTCquGP/BX5iF6ak27hxg0lrS1kI="
      },
      {
        "virtualPath": "System.Collections.Specialized.wasm",
        "name": "System.Collections.Specialized.wasm",
        "hash": "sha256-tYfQFLMXIhUfxzC1/MucxxvZhm7rDp9UcYL5OVsMXAo="
      },
      {
        "virtualPath": "System.ComponentModel.wasm",
        "name": "System.ComponentModel.wasm",
        "hash": "sha256-gROd1mGPH8FaEgzh0nUJBEL8MD/doQc5GIW6YJYD3W4="
      },
      {
        "virtualPath": "System.ComponentModel.Primitives.wasm",
        "name": "System.ComponentModel.Primitives.wasm",
        "hash": "sha256-X6myAlfbn55/4GpxKGpMoMJ7mmdMRO7Mv+1WwqTbN58="
      },
      {
        "virtualPath": "System.ComponentModel.TypeConverter.wasm",
        "name": "System.ComponentModel.TypeConverter.wasm",
        "hash": "sha256-JDL3UUQr61ZMGwPXA5V2qEPl6/Rkv29lHTcINoZAK9Y="
      },
      {
        "virtualPath": "System.Console.wasm",
        "name": "System.Console.wasm",
        "hash": "sha256-BKvi2SCeangCPna4OkB47YqN+LFpS2j8Lxl/v1slFXI="
      },
      {
        "virtualPath": "System.Diagnostics.Process.wasm",
        "name": "System.Diagnostics.Process.wasm",
        "hash": "sha256-SjJFXAQjESiGqIWWk7Ttha8JiAIAD3GDRJaj9Cq3lAo="
      },
      {
        "virtualPath": "System.wasm",
        "name": "System.wasm",
        "hash": "sha256-y7NnWh8z8gPuKAQI4hhBL69y2e7NlYbHZDvyDbFBTHI="
      },
      {
        "virtualPath": "System.IO.FileSystem.Watcher.wasm",
        "name": "System.IO.FileSystem.Watcher.wasm",
        "hash": "sha256-tOXyzRxYop1LgPA1aFkhLJEoX4x6iGK+m5ssHnATQ+Y="
      },
      {
        "virtualPath": "System.IO.Pipelines.wasm",
        "name": "System.IO.Pipelines.wasm",
        "hash": "sha256-YUHUP3fb8mUiEFOdfQqM/stc3OxmfyDdEIl8P1n6F5o="
      },
      {
        "virtualPath": "System.Linq.wasm",
        "name": "System.Linq.wasm",
        "hash": "sha256-juW3bO5pyME8gb0YZnJ9f966uCMDFifuAY6DSADUaqA="
      },
      {
        "virtualPath": "System.Linq.Expressions.wasm",
        "name": "System.Linq.Expressions.wasm",
        "hash": "sha256-mv1P2qdiGpa0jv2juxjTEELdC+jejCMx/I11hmTQzec="
      },
      {
        "virtualPath": "System.Memory.wasm",
        "name": "System.Memory.wasm",
        "hash": "sha256-YwnJJ/PGXcomRqFORkX4rc3/tIi2S3gcw8uNCIggjdo="
      },
      {
        "virtualPath": "System.ObjectModel.wasm",
        "name": "System.ObjectModel.wasm",
        "hash": "sha256-FgxYy7IHE8BR9GSODqgn2s/oXKngA5IPExJcZLVEtYE="
      },
      {
        "virtualPath": "System.Private.Uri.wasm",
        "name": "System.Private.Uri.wasm",
        "hash": "sha256-ffgt+X/goEhK+8MZMG5f0esxjmFKYd5zKqDfcKM5M28="
      },
      {
        "virtualPath": "System.Security.Claims.wasm",
        "name": "System.Security.Claims.wasm",
        "hash": "sha256-j4cTAb1QetoE4AhdIp/wL7Xu682EKl6NoqRYo1c7h58="
      },
      {
        "virtualPath": "System.Security.Cryptography.wasm",
        "name": "System.Security.Cryptography.wasm",
        "hash": "sha256-qkaANA5bLUOjH4PJozkBggo7cQxjIbIKUxxwg+wW/ps="
      },
      {
        "virtualPath": "System.Text.Encodings.Web.wasm",
        "name": "System.Text.Encodings.Web.wasm",
        "hash": "sha256-KJFRuzNCxhSw/7ZFmSAI0MeJwJNWz8/H4K7pcR/XO1U="
      },
      {
        "virtualPath": "System.Text.Json.wasm",
        "name": "System.Text.Json.wasm",
        "hash": "sha256-rJ9j6zXRF+HD99F1HTpD/j00ydw5z0tdgzGRU0figaM="
      },
      {
        "virtualPath": "System.Threading.Channels.wasm",
        "name": "System.Threading.Channels.wasm",
        "hash": "sha256-3omBKPppSkM26u3F+e1lo39W0C+7QVp5LnII8HwSenc="
      },
      {
        "virtualPath": "System.Threading.Tasks.Parallel.wasm",
        "name": "System.Threading.Tasks.Parallel.wasm",
        "hash": "sha256-Agm6YyBWH7lnwT7n/n7v7qHT0UBxGQCgaBaX3flwvSQ="
      }
    ]
  },
  "debugLevel": 0,
  "globalizationMode": "invariant",
  "runtimeConfig": {
    "runtimeOptions": {
      "configProperties": {
        "Microsoft.Extensions.DependencyInjection.VerifyOpenGenericServiceTrimmability": true,
        "System.ComponentModel.DefaultValueAttribute.IsSupported": false,
        "System.ComponentModel.Design.IDesignerHost.IsSupported": false,
        "System.ComponentModel.TypeConverter.EnableUnsafeBinaryFormatterInDesigntimeLicenseContextSerialization": false,
        "System.ComponentModel.TypeDescriptor.IsComObjectDescriptorSupported": false,
        "System.Data.DataSet.XmlSerializationIsSupported": false,
        "System.Diagnostics.Debugger.IsSupported": false,
        "System.Diagnostics.Metrics.Meter.IsSupported": false,
        "System.Diagnostics.Tracing.EventSource.IsSupported": false,
        "System.Globalization.Invariant": true,
        "System.TimeZoneInfo.Invariant": false,
        "System.Globalization.PredefinedCulturesOnly": true,
        "System.Linq.Enumerable.IsSizeOptimized": true,
        "System.Net.Http.EnableActivityPropagation": false,
        "System.Net.Http.WasmEnableStreamingResponse": true,
        "System.Net.SocketsHttpHandler.Http3Support": false,
        "System.Reflection.Metadata.MetadataUpdater.IsSupported": false,
        "System.Resources.ResourceManager.AllowCustomResourceTypes": false,
        "System.Resources.UseSystemResourceKeys": true,
        "System.Runtime.CompilerServices.RuntimeFeature.IsDynamicCodeSupported": true,
        "System.Runtime.InteropServices.BuiltInComInterop.IsSupported": false,
        "System.Runtime.InteropServices.EnableConsumingManagedCodeFromNativeHosting": false,
        "System.Runtime.InteropServices.EnableCppCLIHostActivation": false,
        "System.Runtime.InteropServices.Marshalling.EnableGeneratedComInterfaceComImportInterop": false,
        "System.Runtime.Serialization.EnableUnsafeBinaryFormatterSerialization": false,
        "System.StartupHookProvider.IsSupported": false,
        "System.Text.Encoding.EnableUnsafeUTF7Encoding": false,
        "System.Text.Json.JsonSerializer.IsReflectionEnabledByDefault": false,
        "System.Threading.Thread.EnableAutoreleasePool": false
      }
    }
  }
}/*json-end*/;