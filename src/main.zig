const Application = @import("Application.zig");
const c = Application.c;
const std = Application.std;

pub fn main() !void {
    var generalPurposeAllocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = generalPurposeAllocator.deinit();

    var application: Application = try Application.init(generalPurposeAllocator.allocator());
    defer application.deinit();

    c.SDL_AddEventWatch(Application.processResize, &application);
    const key: [*]const u8 = c.SDL_GetKeyboardState(null);

    while (application.state != .quiting) {
        while (application.processEvent()) {
        }
        application.processInput(key);
        application.processFrame();
    }
}
