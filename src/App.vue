<template>
  <canvas ref="canvas" style="width: 100vw; height: 100vh" />
</template>
<script setup lang="ts">
import { onMounted, useTemplateRef } from "vue";
import { createDefaultEngine } from "./helpers/babylon/createDefaultEngine.ts";
import {
  initMesh,
  generateTendrilsFromMesh,
} from "./app/hairSimulation/createMesh.ts";
import { SEGMENT_LENGTH, Y_THRESHOLD } from "./app/hairSimulation/constants.ts";
import { SimulationParams } from "./app/hairSimulation/simulationParams.ts";
import { createComputeShader } from "./app/hairSimulation/createComputeShader.ts";
import * as BABYLON from "babylonjs";
import { initLineSystem } from "./app/hairSimulation/createLineSystem";

const canvas = useTemplateRef("canvas");
onMounted(async () => {
  if (!canvas.value) return;
  const engine = await createDefaultEngine(canvas.value);
  const scene = new BABYLON.Scene(engine);
  const camera = new BABYLON.ArcRotateCamera(
    "camera",
    0,
    Math.PI / 2,
    5,
    BABYLON.Vector3.Zero(),
    scene,
  );

  camera.lowerRadiusLimit = 2;
  camera.upperRadiusLimit = 10;

  camera.attachControl(canvas, true);

  const light = new BABYLON.HemisphericLight(
    "light",
    new BABYLON.Vector3(1, 1, 0),
    scene,
  );

  const params = new SimulationParams();

  const mesh = initMesh(scene);
  const tendrils = generateTendrilsFromMesh(
    mesh,
    Y_THRESHOLD,
    SEGMENT_LENGTH,
    params.controlPointsPerStrand,
    25,
  );

  if (!tendrils) return;
  params.activeTendrilCount = tendrils.activeTendrilCount;

  const numTendrils = tendrils.sampleCount;
  const workGroupSize = 256;
  const numWorkgroupsX = Math.ceil(numTendrils / workGroupSize);
  const computeShader = createComputeShader(engine);

  const positionsBuffer = new BABYLON.StorageBuffer(
    engine,
    tendrils.tendrilPositions.byteLength,
    BABYLON.Constants.BUFFER_CREATIONFLAG_VERTEX |
      BABYLON.Constants.BUFFER_CREATIONFLAG_WRITE |
      BABYLON.Constants.BUFFER_CREATIONFLAG_READ,
  );
  positionsBuffer.update(tendrils.tendrilPositions);

  const previousPositionsBuffer = new BABYLON.StorageBuffer(
    engine,
    tendrils.tendrilPreviousPositions.byteLength,
  );
  previousPositionsBuffer.update(tendrils.tendrilPreviousPositions);

  const metaBuffer = new BABYLON.StorageBuffer(
    engine,
    tendrils.tendrilMeta.byteLength,
  );
  metaBuffer.update(tendrils.tendrilMeta);

  const paramsBuffer = new BABYLON.UniformBuffer(
    engine,
    undefined,
    undefined,
    "params",
  );

  let previousOriginMatrix = BABYLON.Matrix.Identity(); // Initialize to identity matrix
  let previousBoneMatrix = BABYLON.Matrix.Identity(); // Initialize to identity matri
  let inverseDeltaTransform = BABYLON.Matrix.Identity();

  paramsBuffer.addUniform("segmentLength", 1);
  paramsBuffer.addUniform("stiffness", 1);
  paramsBuffer.addUniform("resistance", 1);
  paramsBuffer.addUniform("deltaTime", 1);
  paramsBuffer.addUniform("controlPointsPerStrand", 1);
  paramsBuffer.addUniform("activeTendrilCount", 1);
  paramsBuffer.addUniform("gravity", 3);
  paramsBuffer.addUniform("octaves", 1);
  paramsBuffer.addUniform("noiseStrength", 1);
  paramsBuffer.addUniform("noiseOffset", 1);
  paramsBuffer.addUniform("inverseDeltaTransform", 16);
  paramsBuffer.addUniform("finalBoneMatrix", 16);
  paramsBuffer.addUniform("inverseTransposeRotationBoneMatrix", 16);
  paramsBuffer.updateFloat("segmentLength", params.segmentLength);
  paramsBuffer.updateFloat("stiffness", params.stiffness);
  paramsBuffer.updateFloat("resistance", params.resistance);
  paramsBuffer.updateFloat("deltaTime", params.deltaTime);
  paramsBuffer.updateInt(
    "controlPointsPerStrand",
    params.controlPointsPerStrand,
  );
  paramsBuffer.updateInt("activeTendrilCount", params.activeTendrilCount);
  paramsBuffer.updateVector3("gravity", params.gravity);
  paramsBuffer.updateInt("octaves", params.controlPointsPerStrand);
  paramsBuffer.updateMatrix("inverseDeltaTransform", inverseDeltaTransform);
  paramsBuffer.updateMatrix("finalBoneMatrix", previousOriginMatrix);
  paramsBuffer.update();

  computeShader.setStorageBuffer("CURRENT_POSITIONS", positionsBuffer);
  computeShader.setStorageBuffer("PREVIOUS_POSITIONS", previousPositionsBuffer);
  computeShader.setUniformBuffer("params", paramsBuffer);
  computeShader.setStorageBuffer("tendrilMeta", metaBuffer);

  const lineSystem = initLineSystem(
    tendrils,
    params.controlPointsPerStrand,
    scene,
    mesh,
  );

  const skeleton = new BABYLON.Skeleton("skeleton", "skeletonID", scene);
  const transformNode = new BABYLON.TransformNode("transformNode", scene);
  const rootBone = new BABYLON.Bone("rootBone", skeleton);
  mesh.skeleton = skeleton;
  lineSystem.parent = mesh;
  lineSystem.attachToBone(rootBone, mesh);

  scene.onBeforeRenderObservable.add(() => {
    const bone_rotate_speed = 0.01;
    let bone_rotate_speed_multiplier = 1;
    rootBone.rotate(
      BABYLON.Axis.Y,
      bone_rotate_speed * bone_rotate_speed_multiplier,
      BABYLON.Space.LOCAL,
    );
  });

  scene.onBeforeRenderObservable.add(() => {
    // Current transformation matrix of the parent mesh
    const currentOriginMatrix = mesh.getWorldMatrix().clone();

    // Calculate the delta transformation (current * inverse(previous))
    const inversePreviousOriginMatrix =
      BABYLON.Matrix.Invert(previousOriginMatrix);
    const deltaTransform = currentOriginMatrix.multiply(
      inversePreviousOriginMatrix,
    );

    // Update the uniform buffer with the inverse delta transformation
    const inverseDeltaTransform =
      BABYLON.Matrix.Invert(deltaTransform).transpose();
    paramsBuffer.updateMatrix("inverseDeltaTransform", inverseDeltaTransform);

    const currentFinalBoneMatrix = rootBone.getAbsoluteMatrix().clone();

    // Calculate the delta transformation (current * inverse(previous))
    const inversePreviousBoneMatrix = BABYLON.Matrix.Invert(previousBoneMatrix);
    const deltaBoneTransform = currentFinalBoneMatrix.multiply(
      inversePreviousBoneMatrix,
    );

    // Extract the rotation part of the matrix for normal transformations
    const rMatrix = BABYLON.Matrix.FromValues(
      deltaBoneTransform.m[0],
      deltaBoneTransform.m[1],
      deltaBoneTransform.m[2],
      0,
      deltaBoneTransform.m[4],
      deltaBoneTransform.m[5],
      deltaBoneTransform.m[6],
      0,
      deltaBoneTransform.m[8],
      deltaBoneTransform.m[9],
      deltaBoneTransform.m[10],
      0,
      0,
      0,
      0,
      1,
    );

    // Calculate the inverse transpose of the rotation matrix
    const inverseTransposeRotationMatrix =
      BABYLON.Matrix.Invert(rMatrix).transpose();

    // Update the uniform buffer with the matrix for transforming normals
    paramsBuffer.updateMatrix(
      "inverseTransposeRotationBoneMatrix",
      inverseTransposeRotationMatrix,
    );
    // Update the uniform buffer with the inverse delta transformation
    paramsBuffer.updateMatrix(
      "finalBoneMatrix",
      deltaBoneTransform.transpose(),
    );

    paramsBuffer.update();

    previousOriginMatrix = currentOriginMatrix.clone();
    previousBoneMatrix = currentFinalBoneMatrix.clone();

    computeShader.dispatchWhenReady(numWorkgroupsX).then(() => {
      console.log("dispatched");
      // Dispatch for 1 workgroup
      positionsBuffer.read().then((updatedPositions) => {
        updatedPositions = new Float32Array(updatedPositions.buffer);
        // debugger
        lineSystem.updateMeshPositions((positions) => {
          for (
            let i = 0;
            i < params.controlPointsPerStrand * params.activeTendrilCount;
            i++
          ) {
            const cpIndex = i * 3;
            positions[i * 3 + 0] = (updatedPositions as Float32Array)[
              cpIndex + 0
            ];
            positions[i * 3 + 1] = (updatedPositions as Float32Array)[
              cpIndex + 1
            ];
            positions[i * 3 + 2] = (updatedPositions as Float32Array)[
              cpIndex + 2
            ];
          }
        }, true);
      });
    });
  });

  engine.runRenderLoop(() => {
    scene.addLight(light);
    scene.render();
  });
});
</script>
