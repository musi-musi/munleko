![logo](media/logo1024.png)

# munleko

voxel game engine in zig and lua


# clonin n buildin
use zig master, have gpu drivers that can handle opengl 3.3
confirmed with zig version 0.11.0-dev.3803+7ad104227

munleko uses submodules for dependency management, make sure to use `--recursive` when cloning


## windows
just `zig build run`, it *should* work

## linux
same as windows, just install glfw3 from your pm of choice

## mac os
you're on your own

# controls
standard wasd and mouse stuff, space goes up, lshift goes down
- \[`\] to unlock mouse
- \[f4\] to toggle fullscreen
- \[f10\] to toggle vsync
- \[z\] to toggle noclip
- \[f\] to cycle between remove and place
- \[mouse 1\] to place/break