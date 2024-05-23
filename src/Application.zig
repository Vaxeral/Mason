const Application = @This();

const zmath = @import("zmath");
pub const std = @import("std");
pub const c = @cImport({
    @cDefine("GL_GLEXT_PROTOTYPES", {});
    @cInclude("GL/glcorearb.h");
    @cInclude("SDL2/SDL.h");
});

window: *c.SDL_Window,
glContext: c.SDL_GLContext,
state: State = .working,
relativeMouseMode: c_uint = c.SDL_TRUE,
glProgram: c_uint = 0,
glArray: c_uint,
glVertexArray: c_uint,
projection: zmath.Mat,
view: zmath.Mat,
camera: Camera,
time: c_uint = 0,
va: zmath.Vec,
vb: zmath.Vec,
arenaAllocator: std.heap.ArenaAllocator,

const State = enum {
    working,
    quiting,
};

pub fn deinit(application: *Application) void {
    application.arenaAllocator.deinit();
}

pub fn init(allocator: std.mem.Allocator) !Application {
    std.debug.print("\n", .{});
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0)
        return error.SDL_Init;

    const window: *c.SDL_Window = c.SDL_CreateWindow("Mason", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 640, 480, c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_RESIZABLE) orelse
        return error.SDL_CreateWindow;
    const glContext: c.SDL_GLContext = c.SDL_GL_CreateContext(window) orelse
        return error.SDL_GL_CreateContext;
    
    if (c.SDL_GL_MakeCurrent(window, glContext) < 0)
        return error.SDL_GL_MakeCurrent;

    if (c.SDL_GL_SetSwapInterval(1) < 0)
        std.debug.print("SDL_GL_SetSwapInterval() < 0: {s}\n", .{c.SDL_GetError()});

    var arenaAllocator = std.heap.ArenaAllocator.init(allocator);

    const data = [_]f32 {

        0.0, 0.0, 0.0, 1.0, 1.0, 1.0,
        0.0, 0.0, 0.0, 1.0, 1.0, 1.0,

        0.0, 0.0, 0.0, 0.5, 0.0, 0.0,
        5.0, 0.0, 0.0, 0.5, 0.0, 0.0,

        0.0, 0.0, 0.0, 0.0, 0.5, 0.0,
        0.0, 5.0, 0.0, 0.0, 0.5, 0.0,
    };

    const va: zmath.Vec = .{ 5.0, 0.0, 0.0, 0.0 };
    const vb: zmath.Vec = .{ 0.0, 5.0, 0.0, 0.0 };

    var glVertexArray: c_uint = undefined;
    c.glGenVertexArrays(1, &glVertexArray);
    c.glBindVertexArray(glVertexArray);

    var glArray: c_uint = undefined;
    c.glGenBuffers(1, &glArray);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, glArray);
    c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(data)), &data, c.GL_STATIC_DRAW);

    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(0));
    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, 6 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    c.glEnableVertexAttribArray(1);

    c.glBindBuffer(c.GL_ARRAY_BUFFER, 0);
    c.glBindVertexArray(0);

    const projection = zmath.perspectiveFovRhGl(std.math.pi / 2.0, 640.0 / 480.0, 0.1, 100.0);

    const camera: Camera = .{
        .rotation = .{ 0.0, 0.0, 0.0, 0.0 },
        .position = .{ 0.0, 0.0, 0.0, 0.0 },
        .fieldOfView = std.math.pi / 2.0,
        .front = undefined,
        .right = undefined,
    };

    var application = Application {
        .window = window,
        .glContext = glContext,
        .glArray = glArray,
        .glVertexArray = glVertexArray,
        .projection = projection,
        .view = zmath.identity(),
        .camera = camera,
        .va = va,
        .vb = vb,
        .arenaAllocator = arenaAllocator,
    };

    if (c.SDL_SetRelativeMouseMode(application.relativeMouseMode) < 0) {
        std.debug.print("SDL_SetRelativeMouseMode() < 0: {s}\n", .{c.SDL_GetError()});
    }

    try application.compileShaders(arenaAllocator.allocator());

    application.camera.update();


    return application;
}

fn compileShaders(application: *Application, allocator: std.mem.Allocator) !void {
    var vertShader: c_uint = undefined;
    var fragShader: c_uint = undefined;
    
    var data: []const u8 = undefined;
    var file: std.fs.File = undefined;
    var size: c_int = undefined;

    {
        file = try std.fs.cwd().openFile("src/main.vert", .{.mode = .read_only});
        defer file.close();
        data = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        size = @intCast(data.len);
        vertShader = c.glCreateShader(c.GL_VERTEX_SHADER);
        c.glShaderSource(vertShader, 1, &data.ptr, &size);
        c.glCompileShader(vertShader);
        var success: c_int = undefined;
        c.glGetShaderiv(vertShader, c.GL_COMPILE_STATUS, &success);
        if (success == c.GL_FALSE) {
            var info: [512]u8 = undefined;
            c.glGetShaderInfoLog(vertShader, 512, null, &info);
            std.debug.print("{s}\n", .{info});
        }
    }

    {
        file = try std.fs.cwd().openFile("src/main.frag", .{.mode = .read_only});
        defer file.close();
        data = try file.reader().readAllAlloc(allocator, std.math.maxInt(usize));
        size = @intCast(data.len);
        fragShader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
        c.glShaderSource(fragShader, 1, &data.ptr, &size);
        c.glCompileShader(fragShader);
        var success: c_int = undefined;
        c.glGetShaderiv(fragShader, c.GL_COMPILE_STATUS, &success);
        if (success == c.GL_FALSE) {
            var info: [512]u8 = undefined;
            c.glGetShaderInfoLog(fragShader, 512, null, &info);
            std.debug.print("{s}\n", .{info});
        }
    }

    const glProgram: c_uint = c.glCreateProgram();
    c.glAttachShader(glProgram, vertShader);
    c.glAttachShader(glProgram, fragShader);
    c.glLinkProgram(glProgram);
    c.glDeleteShader(vertShader);
    c.glDeleteShader(fragShader);

    application.glProgram = glProgram;
}

pub fn processEvent(application: *Application) bool {
    var event: c.SDL_Event = undefined;
    if (c.SDL_PollEvent(&event) == 0)
        return false;

    switch (event.type) {
        c.SDL_WINDOWEVENT => {
            application.processWindowEvent(event.window);
        },
        c.SDL_KEYUP, c.SDL_KEYDOWN => {
            application.processKeyboardEvent(event.key);
        },
        else => {

        },
    }
    return true;
}

pub fn processInput(application: *Application, key: [*]const u8) void {
    application.time = @intCast(c.SDL_GetTicks());
    const camera: *Camera = &application.camera;
    if (key[c.SDL_SCANCODE_A] == 1) {
    }

    var mouse: MouseState = undefined;
    
    // Keep, calling this to eat relative mouse events, otherwise when switching
    // mouse modes the camera will be affected when we dont want it to be.
    mouse.button = c.SDL_GetRelativeMouseState(&mouse.x, &mouse.y);
    
    if (application.relativeMouseMode == c.SDL_TRUE) {
        // if no change in x and y do not update camera!
        if (mouse.x == 0 and mouse.y == 0) {
            // do nothing.
        } else {
            const xAxisRot: Radians = -@as(f32, @floatFromInt(mouse.y)) * std.math.tau / 360.0;
            const yAxisRot: Radians =  @as(f32, @floatFromInt(mouse.x)) * std.math.tau / 360.0;
            camera.rotation[0] += xAxisRot;
            camera.rotation[1] += yAxisRot;
            camera.update();
        }

        if (key[c.SDL_SCANCODE_LEFT] == 1) {
            camera.position -= camera.right * @as(zmath.Vec, @splat(1.0));
        }
        if (key[c.SDL_SCANCODE_RIGHT] == 1) {
            camera.position += camera.right * @as(zmath.Vec, @splat(1.0));
        }
        if (key[c.SDL_SCANCODE_UP] == 1) {
            camera.position += camera.front * @as(zmath.Vec, @splat(1.0));
        }
        if (key[c.SDL_SCANCODE_DOWN] == 1) {
            camera.position -= camera.front * @as(zmath.Vec, @splat(1.0));
        }
        application.view = zmath.lookAtRh(camera.position, camera.position + camera.front, .{0.0, 1.0, 0.0, 0.0});
    }

    // if (mouse.button & c.SDL_BUTTON(1) != 0) {
    //     std.debug.print("{s}\n", .{"Left Mouse Button Pressed!"});
    // }
}

pub fn processFrame(application: *Application) void {
    c.glClearColor(0.2, 0.2, 0.2, 1.0);
    c.glClear(c.GL_COLOR_BUFFER_BIT);
    c.glUseProgram(application.glProgram);
    c.glUniformMatrix4fv(c.glGetUniformLocation(application.glProgram, "projection"), 1, c.GL_FALSE, &zmath.matToArr(application.projection));
    c.glUniformMatrix4fv(c.glGetUniformLocation(application.glProgram, "view"), 1, c.GL_FALSE, &zmath.matToArr(application.view));
    c.glUniform1ui(c.glGetUniformLocation(application.glProgram, "time"), application.time);
    c.glUniform3fv(c.glGetUniformLocation(application.glProgram, "va"), 1, &zmath.vecToArr3(application.va));
    c.glUniform3fv(c.glGetUniformLocation(application.glProgram, "vb"), 1, &zmath.vecToArr3(application.vb));
    
    c.glBindVertexArray(application.glVertexArray);
    c.glDrawArrays(c.GL_LINES, 0, 6);
    c.SDL_GL_SwapWindow(application.window);
}

pub fn processResize(userdata: ?*anyopaque, event: [*c]c.SDL_Event) callconv(.C) c_int {
    if (event.*.type == c.SDL_WINDOWEVENT and event.*.window.event == c.SDL_WINDOWEVENT_RESIZED) {
        const application: *Application = @alignCast(@ptrCast(userdata));
        const window: *c.SDL_Window = c.SDL_GetWindowFromID(event.*.window.windowID) orelse
            return 0;
        if (application.window == window) {
            const w = event.*.window.data1;
            const h = event.*.window.data2;
            c.glViewport(0, 0, w, h);
            const aspectRatio: f32 = @as(f32, @floatFromInt(w)) / @as(f32, @floatFromInt(h));
            const fieldOfView: Radians = std.math.pi / 2.0;
            const near: f32 = 0.1;
            const far: f32 = 100.0;
            // zmath.perspectiveFovRhGl doesn't like an aspect ratio of zero.
            if (!std.math.approxEqAbs(f32, aspectRatio, 0.0, 0.01))
                application.projection = zmath.perspectiveFovRhGl(fieldOfView, aspectRatio, near, far);
        }
    }
    return 0;
}

fn processWindowEvent(application: *Application, windowEvent: c.SDL_WindowEvent) void {
    switch (windowEvent.event) {
        c.SDL_WINDOWEVENT_CLOSE => {
            application.state = .quiting;
        },
        else => {

        },
    }
}

const KeyState = enum(u8) {
    pressed,
    released,
};


fn keyEvent(scancode: c.SDL_Scancode, state: c_int) u18 {
    comptime {
        const keyState: KeyState = if (state == c.SDL_PRESSED) .pressed else .released;
        return @as(u18, @bitCast(KeyEvent{.scancode = @intCast(scancode), .state = keyState}));
    }
}

fn keyEventFromSdl(keyboardEvent: c.SDL_KeyboardEvent) u18 {
    const scancode: u10 = @intCast(keyboardEvent.keysym.scancode);
    const state: KeyState = if (keyboardEvent.state == c.SDL_PRESSED) .pressed else .released;
    return @as(u18, @bitCast(KeyEvent{.scancode = scancode, .state = state}));
}

const KeyEvent = packed struct {
    scancode: std.math.IntFittingRange(0, c.SDL_NUM_SCANCODES),
    state: KeyState,
};

fn processKeyboardEvent(application: *Application, keyboardEvent: c.SDL_KeyboardEvent) void {
    if (keyboardEvent.repeat != 0)
        return;
    const event = keyEventFromSdl(keyboardEvent);
    switch (event) {
        keyEvent(c.SDL_SCANCODE_Q, c.SDL_PRESSED) => {
            application.state = .quiting;
        },
        keyEvent(c.SDL_SCANCODE_T, c.SDL_RELEASED) => {
            application.toggleRelativeMouseMode() catch {};
        },
        keyEvent(c.SDL_SCANCODE_T, c.SDL_PRESSED) => {
            // application.toggleRelativeMouseMode() catch {};
        },
        keyEvent(c.SDL_SCANCODE_C, c.SDL_PRESSED) => {
            application.compileShaders(application.arenaAllocator.allocator()) catch {};
        },
        else => {

        },
    }
}

fn toggleRelativeMouseMode(application: *Application) !void {
    const relativeMouseMode: c_uint = block: {
        if (application.relativeMouseMode == c.SDL_TRUE) {
            break :block c.SDL_FALSE;
        } else {
            break :block c.SDL_TRUE;
        }
    };
    if (c.SDL_SetRelativeMouseMode(relativeMouseMode) < 0) {
        std.debug.print("SDL_SetRelativeMouseMode() < 0: {s}\n", .{c.SDL_GetError()});
        return error.SDL_SetRelativeMouseMode;
    } else {
        application.relativeMouseMode = relativeMouseMode;
    }
}

const Global = struct {
    var i: zmath.Vec = .{ 1, 0, 0, 0 };
    var j: zmath.Vec = .{ 0, 1, 0, 0 };
    var k: zmath.Vec = .{ 0, 0, 1, 0 };
};

const Radians = f32;

const Camera = struct {
    rotation: zmath.Vec,
    position: zmath.Vec,
    fieldOfView: Radians,
    front: zmath.Vec,
    right: zmath.Vec,
    pub fn update(camera: *Camera) void {
        if (camera.rotation[0] >  89.0 * std.math.pi / 180.0) {
            camera.rotation[0] =  89.0 * std.math.pi / 180.0;
        }
        if (camera.rotation[0] < -89.0 * std.math.pi / 180.0) {
            camera.rotation[0] = -89.0 * std.math.pi / 180.0;
        }

        const xAxisRot = camera.rotation[0];
        const yAxisRot = camera.rotation[1];

        camera.front[0] = std.math.cos(yAxisRot) * std.math.cos(xAxisRot);
        camera.front[1] = std.math.sin(xAxisRot);
        camera.front[2] = std.math.sin(yAxisRot) * std.math.cos(xAxisRot);
        camera.front = zmath.normalize3(camera.front);
        camera.right = zmath.normalize3(zmath.cross3(camera.front, .{ 0.0, 1.0, 0.0, 0.0 }));
    }
};

const MouseState = struct {
    x: c_int,
    y: c_int,
    button: u32,
};
