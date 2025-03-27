// Sphere SDF function
fn sdfSphere(point: vec3<f32>, center: vec3<f32>, radius: f32) -> f32 {
    return length(point - center) - radius;
}

// Collision response
fn resolveCollision(point: vec3<f32>, center: vec3<f32>, radius: f32) -> vec3<f32> {
    let direction = normalize(point - center); // Direction from sphere center to point
    return center + direction * radius;       // Project point to the sphere surface
}

// Sphere parameters
const sphereCenter = vec3<f32>(0.0, 0.0, 0.0);
const sphereRadius: f32 = 0.6;

// Global simulation parameters
struct SimulationParams {
    segmentLength: f32,
    stiffness: f32,
    resistance: f32,
    deltaTime: f32,
    controlPointsPerStrand: u32,
    activeTendrilCount: u32,
    gravity: vec3f,
    octaves: i32,
    noiseStrength: f32,
    noiseOffset: f32,
    inverseDeltaTransform: mat4x4<f32>,
    finalBoneMatrix: mat4x4<f32>,
    inverseTransposeRotationBoneMatrix: mat4x4<f32>,
};

// Metadata for tendrils
struct TendrilData {
    rootNormal: vec3<f32>,
};


fn accumulateForces(
    currentPosition: vec3<f32>,
    previousNeighborPosition: vec3<f32>,
    nextNeighborPosition: vec3<f32>,
    previousPosition: vec3<f32>,
    velocity: vec3<f32>
) -> vec3<f32> {
    var totalForce = vec3<f32>(0.0);

    // Gravity
    totalForce += params.gravity;



    let periodicity = vec3<f32>(1, 1, 1); // Periodicity every 10 units in each axis 
    let rotation = 2.0; // Rotation angle in radians7

    // Strand direction (based on neighbors)
    let hairDirection = normalize((nextNeighborPosition - currentPosition) + (currentPosition - previousNeighborPosition));

    // Decompose velocity
    let velocityParallel = dot(velocity, hairDirection) * hairDirection;
    let velocityPerpendicular = velocity - velocityParallel;

    // Directional drag
    let parallelResistance = 120.1 * params.resistance;  // Low drag along the strand
    let perpendicularResistance = 200.0 * params.resistance; // High drag orthogonal to the strand
    let dragForce = -velocityParallel * parallelResistance - velocityPerpendicular * perpendicularResistance;

    // Add drag to total force
    totalForce += dragForce;

    return totalForce;
}


@group(0) @binding(0) var<storage, read_write> CURRENT_POSITIONS: array<f32>;
@group(0) @binding(1) var<storage, read_write> PREVIOUS_POSITIONS: array<f32>;
@group(0) @binding(2) var<uniform> params: SimulationParams;
@group(0) @binding(3) var<storage, read> tendrilMeta: array<f32>;


@compute @workgroup_size(256)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {

    let tendrilIndex = global_id.x;

    if tendrilIndex >= params.activeTendrilCount {
        return;
    }

    let tendril_data_start_idx = tendrilIndex * params.controlPointsPerStrand * 3u;

    // Load the entire tendril into a local variable
    var tendrilCurrentPositions: array<vec3<f32>, 64>; // Adjust size to max control points
    var tendrilPreviousPositions: array<vec3<f32>, 64>; // Same as above

    for (var idx: u32 = 0; idx < params.controlPointsPerStrand; idx++) {
        let baseIdx = tendril_data_start_idx + (idx * 3u);
        tendrilCurrentPositions[idx] = vec3<f32>(
            CURRENT_POSITIONS[baseIdx + 0],
            CURRENT_POSITIONS[baseIdx + 1],
            CURRENT_POSITIONS[baseIdx + 2]
        );
        tendrilPreviousPositions[idx] = vec3<f32>(
            PREVIOUS_POSITIONS[baseIdx + 0],
            PREVIOUS_POSITIONS[baseIdx + 1],
            PREVIOUS_POSITIONS[baseIdx + 2]
        );
    }

    let _usage = tendrilMeta[0];
    // Compute the new root normal based on the updated root position and the first segment
    var ROOT_POSITION = tendrilCurrentPositions[0];

    let rootNormal = normalize(ROOT_POSITION - sphereCenter);

    for (var idx: u32 = 1; idx < params.controlPointsPerStrand; idx++) {

        var currentPosition = (vec4<f32>(
            tendrilCurrentPositions[idx],
            1.
        ) * params.inverseDeltaTransform).xyz;


        var previousPositionVec = (vec4<f32>(
            tendrilPreviousPositions[idx],
            1.
        ) * params.inverseDeltaTransform).xyz;
        tendrilPreviousPositions[idx] = previousPositionVec;

        let previousPosition = vec3<f32>(
            tendrilPreviousPositions[idx]
        );

        // Fetch neighbors
        var previousNeighborPosition = vec3<f32>(0.0);
        var nextNeighborPosition = vec3<f32>(0.0);

        if idx > 0 {
            // Previous neighbor exists
            let prevIdx = idx - 1;
            previousNeighborPosition = (vec4<f32>(
                tendrilCurrentPositions[prevIdx], 1.
            ) * params.inverseDeltaTransform).xyz;
        } else {
            // For root, use current position (no prior neighbor)
            previousNeighborPosition = currentPosition;
        }

        if idx < params.controlPointsPerStrand - 1 {
            // Next neighbor exists
            let nextIdx = idx + 1;
            nextNeighborPosition = (vec4<f32>(
                tendrilCurrentPositions[nextIdx], 1.
            ) * params.inverseDeltaTransform).xyz;
        } else {
            // For tip, use current position (no next neighbor)
            nextNeighborPosition = currentPosition;
        }

        // Compute velocity
        let velocity = currentPosition - previousPosition;

        // Accumulate forces
        let totalForce = accumulateForces(
            currentPosition,
            previousNeighborPosition,
            nextNeighborPosition,
            previousPosition,
            velocity
        );

        // Verlet integration
        var newPosition = currentPosition + velocity + totalForce * params.deltaTime * params.deltaTime;


        // Update positions
        tendrilPreviousPositions[idx] = currentPosition;
        tendrilCurrentPositions[idx] = newPosition;
    }

    // Bone matrix application to root vertex
    var currentPosition = (vec4<f32>(
        tendrilCurrentPositions[0], 1.
    ) * params.finalBoneMatrix).xyz;

    tendrilCurrentPositions[0] = currentPosition;

    // Constraint resolution
    for (var iteration: u32 = 0; iteration < 50; iteration++) {
        for (var idx: u32 = 1; idx < params.controlPointsPerStrand; idx++) {

            let currentPosition = tendrilCurrentPositions[idx];
            let previousPosition = tendrilCurrentPositions[idx - 1u];

            // Sphere collision constraint
            let distanceToSphere = sdfSphere(currentPosition, sphereCenter, sphereRadius);
            if distanceToSphere < 0.0 {
                let correctedPosition = resolveCollision(currentPosition, sphereCenter, sphereRadius);
                tendrilCurrentPositions[idx] = correctedPosition;
            }

            // Distance constraint
            let direction = currentPosition - previousPosition;
            let distance = length(direction);
            let distanceError = distance - params.segmentLength;

            if distance > 0.0 {
                let correction = (distanceError / distance) * 0.5;
                let correctionVector = direction * correction;

                if idx != 1 {
                    tendrilCurrentPositions[idx - 1u] += correctionVector;
                }
                tendrilCurrentPositions[idx] -= correctionVector;
            }
        }
    }

    // Apply stiffness at the end
    for (var idx: u32 = 1; idx < params.controlPointsPerStrand; idx++) {

        let currentPosition = tendrilCurrentPositions[idx];
        let previousPosition = tendrilCurrentPositions[idx - 1u];

        // Invert the distance factor for root-to-tip falloff
        let distanceFactor = f32(idx) / f32(params.controlPointsPerStrand * 2);
        let invertedFactor = 1.0 - distanceFactor;

        // Apply ease-in cubic to the inverted factor
        let stiffnessInfluence = params.stiffness * easeOutCubic(invertedFactor) * 0.01;

        let alignedPosition = alignToRootNormal(
            currentPosition,
            rootNormal,
            previousPosition,
            params.segmentLength,
            stiffnessInfluence
        );

        tendrilCurrentPositions[idx] = alignedPosition;
    }

    for (var idx: u32 = 0; idx < params.controlPointsPerStrand; idx++) {
        let baseIdx = tendril_data_start_idx + idx * 3u;
        CURRENT_POSITIONS[baseIdx] = tendrilCurrentPositions[idx].x;
        CURRENT_POSITIONS[baseIdx + 1] = tendrilCurrentPositions[idx].y;
        CURRENT_POSITIONS[baseIdx + 2] = tendrilCurrentPositions[idx].z;
        PREVIOUS_POSITIONS[baseIdx] = tendrilPreviousPositions[idx].x;
        PREVIOUS_POSITIONS[baseIdx + 1] = tendrilPreviousPositions[idx].y;
        PREVIOUS_POSITIONS[baseIdx + 2] = tendrilPreviousPositions[idx].z;
    }
}


fn alignToRootNormal(
    currentPosition: vec3<f32>,
    rootNormal: vec3<f32>,
    rootToPrev: vec3<f32>,
    segmentLength: f32,
    stiffness: f32
) -> vec3<f32> {
    // Project the current position onto the root-normal axis
    let projection = dot(currentPosition, rootNormal) * rootNormal;
    let targetPosition = projection + rootToPrev; // Maintain relative segment offset
    // Interpolate between the current position and the target position
    let correctedPosition = mix(currentPosition, targetPosition, stiffness);

    // Normalize the segment length
    let correctedDirection = normalize(correctedPosition - rootToPrev);
    return rootToPrev + correctedDirection * segmentLength;
}


fn falloffCurve(t: f32) -> f32 {
    // Use a smoothstep-based falloff for now
    return smoothstep(0.0, 1.0, 1.0 - t);
}

fn easeOutCubic(t: f32) -> f32 {
    return 1.0 - pow(1.0 - t, 3.0);
}


