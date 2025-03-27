export const createPositionsBuffer = (engine: BABYLON.WebGPUEngine) => {
  const positionsBuffer = new BABYLON.StorageBuffer(
    engine,
    tendrilData.tendrilPositions.byteLength,
    BABYLON.Constants.BUFFER_CREATIONFLAG_VERTEX |
      BABYLON.Constants.BUFFER_CREATIONFLAG_WRITE |
      BABYLON.Constants.BUFFER_CREATIONFLAG_READ,
  );
  positionsBuffer.update(tendrilData.tendrilPositions);
};
