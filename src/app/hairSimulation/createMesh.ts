import * as BABYLON from "babylonjs";
export const initMesh = (scene: BABYLON.Scene) => {
  const pointerDragBehavior = new BABYLON.PointerDragBehavior();

  pointerDragBehavior.useObjectOrientationForDragging = false;
  const mesh = BABYLON.MeshBuilder.CreateIcoSphere("mesh", {
    radius: 0.59,
    subdivisions: 24,
  });

  const pbr = new BABYLON.PBRMaterial("pbr", scene);
  mesh.material = pbr;

  pbr.albedoColor = new BABYLON.Color3(0.1, 0.1, 0.1);
  pbr.metallic = 1.0;
  pbr.roughness = 0.3;

  pbr.iridescence.isEnabled = true;

  mesh.addBehavior(pointerDragBehavior);
  mesh.receiveShadows = true;

  const vertexCount = mesh.getTotalVertices();
  const weights = new Float32Array(vertexCount * 16);
  const indices = new Float32Array(vertexCount);

  for (let i = 0; i < vertexCount; i++) {
    indices[i] = 0; // Single bone index
  }

  for (let i = 0; i < vertexCount * 16; i++) {
    weights[i] = 1; // Single bone index
  }

  mesh.setVerticesData(BABYLON.VertexBuffer.MatricesWeightsKind, weights, true);
  mesh.setVerticesData(BABYLON.VertexBuffer.MatricesIndicesKind, indices, true);

  return mesh;
};

export const generateTendrilsFromMesh = (
  mesh: BABYLON.Mesh,
  yThreshold: number,
  SEGMENT_LENGTH: number,
  controlPointsPerStrand: number,
  percentage = 100,
) => {
  const positions = mesh.getVerticesData(BABYLON.VertexBuffer.PositionKind);
  let normals = mesh.getVerticesData(BABYLON.VertexBuffer.NormalKind);
  if (!positions) return undefined;

  // Calculate mesh center if normals are not available
  let center = new BABYLON.Vector3(0, 0, 0);
  if (!normals) {
    const vertexCount = positions.length / 3;
    for (let i = 0; i < vertexCount; i++) {
      center.x += positions[i * 3];
      center.y += positions[i * 3 + 1];
      center.z += positions[i * 3 + 2];
    }
    center.scaleInPlace(1 / vertexCount);
    normals = new Float32Array(positions.length);
  }

  const tendrilPositions = [];
  const tendrilPreviousPositions = [];
  const tendrilMeta = [];
  const vertexToControlPointMap = [];
  let activeTendrilCount = 0;

  // Calculate the number of vertices to sample based on the percentage
  const vertexCount = positions.length / 3;
  const sampleCount = Math.floor((percentage / 100) * vertexCount);

  // Shuffle vertex indices to randomly sample the vertices
  const vertexIndices = Array.from({ length: vertexCount }, (_, i) => i);
  for (let i = vertexIndices.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [vertexIndices[i], vertexIndices[j]] = [vertexIndices[j], vertexIndices[i]];
  }

  // Iterate over the sampled vertices
  for (let sampleIndex = 0; sampleIndex < sampleCount; sampleIndex++) {
    const vertexIndex = vertexIndices[sampleIndex];
    const x = positions[vertexIndex * 3];
    const y = positions[vertexIndex * 3 + 1];
    const z = positions[vertexIndex * 3 + 2];

    if (y > yThreshold) {
      const rootControlPointIndex =
        activeTendrilCount * controlPointsPerStrand * 3;
      vertexToControlPointMap.push({
        vertexIndex,
        controlPointIndex: rootControlPointIndex,
      });

      activeTendrilCount++;

      let normalX: number, normalY: number, normalZ: number;
      if (normals[vertexIndex * 3] === undefined) {
        // Calculate normal as the direction from center to vertex
        const direction = new BABYLON.Vector3(x, y, z)
          .subtract(center)
          .normalize();
        normalX = direction.x;
        normalY = direction.y;
        normalZ = direction.z;

        normals[vertexIndex * 3] = normalX;
        normals[vertexIndex * 3 + 1] = normalY;
        normals[vertexIndex * 3 + 2] = normalZ;
      } else {
        normalX = normals[vertexIndex * 3];
        normalY = normals[vertexIndex * 3 + 1];
        normalZ = normals[vertexIndex * 3 + 2];
      }

      const rootPosition = new BABYLON.Vector3(x, y, z);
      const rootNormal = new BABYLON.Vector3(normalX, normalY, normalZ);

      for (let j = 0; j < controlPointsPerStrand; j++) {
        const distance = SEGMENT_LENGTH * j; // Fixed segment length
        const tendrilPosition = rootPosition.add(rootNormal.scale(distance));

        tendrilPositions.push(
          tendrilPosition.x,
          tendrilPosition.y,
          tendrilPosition.z,
        );
        tendrilPreviousPositions.push(
          tendrilPosition.x,
          tendrilPosition.y,
          tendrilPosition.z,
        ); // Initial previous positions at origin
      }

      // Tendril metadata (identity matrix and root direction)
      tendrilMeta.push(
        rootNormal.x,
        rootNormal.y,
        rootNormal.z,
        0, // rootNormal
      );
    }
  }

  return {
    tendrilPositions: new Float32Array(tendrilPositions),
    tendrilPreviousPositions: new Float32Array(tendrilPreviousPositions),
    tendrilMeta: new Float32Array(tendrilMeta),
    vertexToControlPointMap, // Return the mapping
    activeTendrilCount,
    sampleCount: tendrilPositions.length / 3,
  };
};
