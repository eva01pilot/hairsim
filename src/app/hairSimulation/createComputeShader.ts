import shader from "./shader.wgsl?raw";
import * as BABYLON from "babylonjs";
export const createComputeShader = (engine: BABYLON.WebGPUEngine) => {
  const computeShader = new BABYLON.ComputeShader(
    "tendrilCompute",
    engine,
    { computeSource: shader },
    {
      bindingsMapping: {
        CURRENT_POSITIONS: { group: 0, binding: 0 },
        PREVIOUS_POSITIONS: { group: 0, binding: 1 },
        params: { group: 0, binding: 2 },
        tendrilMeta: { group: 0, binding: 3 },
      },
    },
  );
  return computeShader;
};
