import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'dart:typed_data';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
      ),
      home: Material(child: TrianglePage()),
    );
  }
}

ByteData float32(List<double> values) {
  return Float32List.fromList(values).buffer.asByteData();
}

ByteData float32Mat(Matrix4 matrix) {
  return Float32List.fromList(matrix.storage).buffer.asByteData();
}

ByteData _zipFloat32(List<dynamic> values) {
  final list = <double>[];

  for (final v in values) {
    if (v is num) list.add(v.toDouble());
    if (v is List<num>) list.addAll(v.map((e) => e.toDouble()));
    if (v is Matrix4) list.addAll(v.storage);
  }

  return Float32List.fromList(list).buffer.asByteData();
}

class TrianglePainter extends CustomPainter {
  TrianglePainter(this.time, this.seedX, this.seedY);

  double time;
  double seedX;
  double seedY;

  @override
  void paint(Canvas canvas, Size size) {
    /// Allocate a new renderable texture.
    final gpu.Texture? renderTexture = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate, 300, 300,
        enableRenderTargetUsage: true,
        enableShaderReadUsage: true,
        coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture);
    if (renderTexture == null) {
      return;
    }

    final gpu.Texture? depthTexture = gpu.gpuContext.createTexture(
        gpu.StorageMode.deviceTransient, 300, 300,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        enableRenderTargetUsage: true,
        coordinateSystem: gpu.TextureCoordinateSystem.renderToTexture);
    if (depthTexture == null) {
      return;
    }

    /// Create the command buffer. This will be used to submit all encoded
    /// commands at the end.
    final commandBuffer = gpu.gpuContext.createCommandBuffer();

    /// Define a render target. This is just a collection of attachments that a
    /// RenderPass will write to.
    final renderTarget = gpu.RenderTarget.singleColor(
      gpu.ColorAttachment(texture: renderTexture),
      depthStencilAttachment: gpu.DepthStencilAttachment(texture: depthTexture),
    );

    /// Add a render pass encoder to the command buffer so that we can start
    /// encoding commands.
    final encoder = commandBuffer.createRenderPass(renderTarget);

    /// Load a shader bundle asset.
    final library = gpu.ShaderLibrary.fromAsset('assets/TestLibrary.shaderbundle')!;

    /// Create a RenderPipeline using shaders from the asset.
    final vertex = library['UnlitVertex']!;
    final fragment = library['UnlitFragment']!;
    final pipeline = gpu.gpuContext.createRenderPipeline(vertex, fragment);

    encoder.bindPipeline(pipeline);

    /// (Optional) Configure blending for the first color attachment.
    encoder.setColorBlendEnable(true);
    encoder.setColorBlendEquation(gpu.ColorBlendEquation(
        colorBlendOperation: gpu.BlendOperation.add,
        sourceColorBlendFactor: gpu.BlendFactor.one,
        destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
        alphaBlendOperation: gpu.BlendOperation.add,
        sourceAlphaBlendFactor: gpu.BlendFactor.one,
        destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha));

    /// Append quick geometry and uniforms to a host buffer that will be
    /// automatically uploaded to the GPU later on.
    final transients = gpu.gpuContext.createHostBuffer();

    final vertices = transients.emplace(float32(<double>[
      -0.5, -0.5, //
      0, 0.5, //
      0.5, -0.5, //
    ]));

    final vertexInfo = transients.emplace(
      _zipFloat32(
        [
          Matrix4(
            1, 0, 0, 0, //
            0, 1, 0, 0, //
            0, 0, 1, 0, //
            0, 0, 0.5, 1, //
          ),
          <double>[1, 1, 1, 0],
        ],
      ),
    );

    encoder.bindVertexBuffer(vertices, 3);

    final vertexInfoSlot = pipeline.vertexShader.getUniformSlot('VertexInfo');
    encoder.bindUniform(vertexInfoSlot, vertexInfo);

    final vertexInfoColorMVP = transients.emplace(
      _zipFloat32(
        [
          Matrix4(
              1, 0, 0, 0, //
              0, 1, 0, 0, //
              0, 0, 1, 0, //
              0, 0, 0.5, 1, //
          ) *
          Matrix4.rotationX(time) *
          Matrix4.rotationY(time * seedX) *
          Matrix4.rotationZ(time * seedY),
          <double>[0, 1, 0, 1],
        ],
      ),
    );

    encoder.bindUniform(vertexInfoSlot, vertexInfoColorMVP);

    /// And finally, we append a draw call.
    encoder.draw();

    /// Submit all of the previously encoded passes. Passes are encoded in the
    /// same order they were created in.
    commandBuffer.submit();

    /// Wrap the Flutter GPU texture as a ui.Image and draw it like normal!
    final image = renderTexture.asImage();

    canvas.drawImage(image, Offset(-renderTexture.width / 2, 0), Paint());
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class TrianglePage extends StatefulWidget {
  const TrianglePage({super.key});

  @override
  State<TrianglePage> createState() => _TrianglePageState();
}

class _TrianglePageState extends State<TrianglePage> {
  Ticker? tick;
  double time = 0;
  double deltaSeconds = 0;
  double seedX = -0.512511498387847167;
  double seedY = 0.521295573094847167;

  @override
  void initState() {
    tick = Ticker(
          (elapsed) {
        setState(() {
          double previousTime = time;
          time = elapsed.inMilliseconds / 1000.0;
          deltaSeconds = previousTime > 0 ? time - previousTime : 0;
        });
      },
    );
    tick!.start();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Slider(
            value: seedX,
            max: 1,
            min: -1,
            onChanged: (value) => {setState(() => seedX = value)}),
        Slider(
            value: seedY,
            max: 1,
            min: -1,
            onChanged: (value) => {setState(() => seedY = value)}),
        CustomPaint(
          painter: TrianglePainter(time, seedX, seedY),
        ),
      ],
    );
  }
}