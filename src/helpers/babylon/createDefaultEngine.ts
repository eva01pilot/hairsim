import * as BABYLON from "babylonjs";
export const createDefaultEngine = async (canvas: HTMLCanvasElement) => {
  const engine = new BABYLON.WebGPUEngine(canvas);
  await engine.initAsync();
  return engine;
};

export const initFunction = async () => {};
