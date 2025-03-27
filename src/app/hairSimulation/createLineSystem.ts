import * as BABYLON from "babylonjs";
import { generateTendrilsFromMesh } from "./createMesh";
export const initLineSystem = (
  tendrilData: NonNullable<ReturnType<typeof generateTendrilsFromMesh>>,
  controlPointsPerStrand: number,
  scene: BABYLON.Scene,
  mesh: BABYLON.Mesh,
) => {
  const tendrilLines = [];
  const tendrilColors = [];
  for (let i = 0; i < tendrilData.activeTendrilCount; i++) {
    const line = [];
    for (let j = 0; j < controlPointsPerStrand; j++) {
      const idx = i * controlPointsPerStrand * 3 + j * 3;
      line.push(
        new BABYLON.Vector3(
          tendrilData.tendrilPositions[idx],
          tendrilData.tendrilPositions[idx + 1],
          tendrilData.tendrilPositions[idx + 2],
        ),
      );
    }
    tendrilLines.push(line);
    tendrilColors.push(
      line.map(
        (_e, i) =>
          new BABYLON.Color4(
            0.1,
            1 - i * (1 / controlPointsPerStrand),
            i * (1 / controlPointsPerStrand),
            1,
          ),
      ),
    );
  }

  const lineSystem = BABYLON.MeshBuilder.CreateLineSystem(
    "lineSystem",
    {
      lines: tendrilLines,
      colors: tendrilColors,
      updatable: true,
    },
    scene,
  );

  const ls_vertexCount = lineSystem.getTotalVertices();
  const ls_weights = new Float32Array(ls_vertexCount);
  const ls_indices = new Float32Array(ls_vertexCount);

  for (let i = 0; i < ls_vertexCount * 3; i++) {
    ls_weights[i] = 1; // Random weight for the bone
    ls_indices[i] = 0; // Single bone index
  }

  lineSystem.setVerticesData(
    BABYLON.VertexBuffer.MatricesWeightsKind,
    ls_weights,
    true,
  );
  lineSystem.setVerticesData(
    BABYLON.VertexBuffer.MatricesIndicesKind,
    ls_indices,
    true,
  );
  return lineSystem;
};
