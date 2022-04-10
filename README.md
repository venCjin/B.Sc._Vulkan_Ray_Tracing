# B.Sc._Vulkan_Ray_Tracing
Vulkan app to use hardware accelerated Ray Tracing. Created as part of Bachelor thesis.

## Bachelor thesis PDF
can be found in [here](docs/Bachelor_thesis_Jarosław_Suchiński.pdf)

## Build from source
Simply create solution folder and run cmake
```
mkdir solution
cd solution
cmake ..
```

## App prebuild for windows
is located in [prebuild_windows_app folder](prebuild_windows_app/) and by default app setup white diffuse material on Lucy. 

It can be changed to mirror material when run with parameter
``` vk_rt_app.exe -lucyMirror ```
or run from shourtcut
``` vk_rt_app_lucy_mirror.exe ```
