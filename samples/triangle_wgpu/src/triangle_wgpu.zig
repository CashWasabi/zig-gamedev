const std = @import("std");
const glfw = @import("glfw");
const gpu = @import("gpu");
const zgpu = @import("zgpu");

const DemoState = struct {
    gctx: *zgpu.GraphicsContext,
    pipeline: gpu.RenderPipeline,
};

fn init(allocator: std.mem.Allocator, window: glfw.Window) DemoState {
    var gctx = zgpu.GraphicsContext.create(allocator, window);

    const vs =
        \\ @stage(vertex) fn main(
        \\     @builtin(vertex_index) VertexIndex : u32
        \\ ) -> @builtin(position) vec4<f32> {
        \\     var pos = array<vec2<f32>, 3>(
        \\         vec2<f32>( 0.0,  0.5),
        \\         vec2<f32>(-0.5, -0.5),
        \\         vec2<f32>( 0.5, -0.5)
        \\     );
        \\     return vec4<f32>(pos[VertexIndex], 0.0, 1.0);
        \\ }
    ;
    const vs_module = gctx.device.createShaderModule(&.{ .label = "vs", .code = .{ .wgsl = vs } });
    defer vs_module.release();

    const fs =
        \\ @stage(fragment) fn main() -> @location(0) vec4<f32> {
        \\     return vec4<f32>(0.0, 0.8, 0.0, 1.0);
        \\ }
    ;
    const fs_module = gctx.device.createShaderModule(&.{ .label = "fs", .code = .{ .wgsl = fs } });
    defer fs_module.release();

    const blend = gpu.BlendState{
        .color = .{ .operation = .add, .src_factor = .one, .dst_factor = .one },
        .alpha = .{ .operation = .add, .src_factor = .one, .dst_factor = .one },
    };
    const color_target = gpu.ColorTargetState{
        .format = gctx.swap_chain_format,
        .blend = &blend,
        .write_mask = .all,
    };
    const fragment = gpu.FragmentState{
        .module = fs_module,
        .entry_point = "main",
        .targets = &.{color_target},
        .constants = null,
    };

    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .layout = null,
        .depth_stencil = null,
        .vertex = .{
            .module = vs_module,
            .entry_point = "main",
            .buffers = null,
        },
        .multisample = .{
            .count = 1,
            .mask = 0xffff_ffff,
            .alpha_to_coverage_enabled = false,
        },
        .primitive = .{
            .front_face = .ccw,
            .cull_mode = .none,
            .topology = .triangle_list,
            .strip_index_format = .none,
        },
    };
    const pipeline = gctx.device.createRenderPipeline(&pipeline_descriptor);

    return .{
        .gctx = gctx,
        .pipeline = pipeline,
    };
}

fn deinit(allocator: std.mem.Allocator, demo: *DemoState) void {
    demo.pipeline.release();
    allocator.destroy(demo.gctx);
    demo.* = undefined;
}

fn draw(demo: *DemoState) void {
    var gctx = demo.gctx;
    gctx.update();

    const back_buffer_view = gctx.swap_chain.?.getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .resolve_target = null,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = gctx.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassEncoder.Descriptor{
        .color_attachments = &.{color_attachment},
        .depth_stencil_attachment = null,
    };
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(demo.pipeline);
    pass.draw(3, 1, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    gctx.device_queue.submit(&.{command});
    command.release();
    gctx.swap_chain.?.present();
    back_buffer_view.release();
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    try glfw.init(.{});
    defer glfw.terminate();

    const window = try glfw.Window.create(1280, 960, "zig-gamedev: triangle wgpu", null, null, .{
        .client_api = .no_api,
        .cocoa_retina_framebuffer = true,
    });

    var demo = init(allocator, window);
    defer deinit(allocator, &demo);

    while (!window.shouldClose()) {
        try glfw.pollEvents();
        draw(&demo);
    }
}