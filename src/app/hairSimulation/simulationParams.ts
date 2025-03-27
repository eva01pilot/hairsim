import * as BABYLON from "babylonjs";
export class SimulationParams {
  segmentLength: number;
  stiffness: number;
  resistance: number;
  deltaTime: number;
  controlPointsPerStrand: number;
  activeTendrilCount: number;
  gravity: BABYLON.Vector3;
  octaves: number;

  constructor(
    controlPointsPerStrand = 24,
    stiffness = 0,
    resistance = 0.5,
    deltaTime = 0.016,
    activeTendrilCount = 1,
    gravity: BABYLON.Vector3 = new BABYLON.Vector3(0, -5.8, 0),
    octaves = 1,
  ) {
    this.controlPointsPerStrand = controlPointsPerStrand;
    this.stiffness = stiffness;
    this.resistance = resistance;
    this.deltaTime = deltaTime;
    this.segmentLength = 2 / this.controlPointsPerStrand;
    this.activeTendrilCount = activeTendrilCount;
    this.gravity = gravity;
    this.octaves = octaves;
  }
}
