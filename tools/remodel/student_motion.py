"""Local rotations (degrees) for the students' shared, in-place glTF clips."""
from math import cos, pi, sin

# Non-looping poses share their end key with the following idle pose.
CLIPS = {
    "idle": 3.2, "walk": 0.98, "run": 0.68, "back": 1.06, "left": 0.88, "right": 0.88,
    "turn_left": 0.72, "turn_right": 0.72, "limp": 1.18, "sit_down": 0.54, "sit": 2.8,
    "stand_up": 0.55, "search": 1.5, "interact": 0.52, "read": 2.4, "type": 1.2,
    "speak": 1.8, "bandage": 1.8, "vault": 0.75, "fall": 0.9, "drive": 1.6,
    "ride": 2.2, "collapse": 0.85, "down": 1.0, "torch": 2.0, "crouch": 1.8,
}
ONE_SHOTS = {"sit_down", "stand_up", "interact", "vault", "collapse"}


def pose(clip, u):
    wave, breath = sin(u * 2 * pi), cos(u * 2 * pi)
    rot = {"Spine": (-1.5 + wave * 0.8, 0, 0), "Head": (1.5, wave * 2, 0)}
    shift = [0, 0.002 * wave, 0]
    for side, sign in (("L", 1), ("R", -1)):
        rot["Arm" + side] = (3.5, 0, 3 * sign)
        rot["Elbow" + side] = (9, 0, 0)
    if clip in {"walk", "run", "back", "left", "right", "limp", "turn_left", "turn_right"}:
        run = clip == "run"
        lateral = (clip == "right") - (clip == "left")
        turn = (clip == "turn_right") - (clip == "turn_left")
        step = 54 if run else 30
        if lateral or turn:
            step = 10 if lateral else 6
        shift = [0.019 * breath, (0.027 if run else 0.014) * (1 - breath**2), 0]
        rot["Hips"] = (1, 6 * wave, -2.8 * breath)
        rot["Chest"] = (-11 if run else -3, -10 * wave - 7 * turn, 2.2 * breath - lateral * 4)
        rot["Head"] = (6 if run else 2, 4 * wave + 7 * turn, 0)
        for side, sign in (("L", 1), ("R", -1)):
            phase = u * 2 * pi + (pi if sign == -1 else 0)
            stride = sin(phase)
            swing = max(0, cos(phase))
            angle = stride * step * (-1 if clip == "back" else 1)
            knee = -4 - (53 if run else 32) * swing
            if clip == "limp" and side == "L":
                angle *= 0.47
                knee *= 0.55
                shift[1] -= max(0, -stride) * 0.042
                rot["Chest"] = (-7, -4 * wave, -6 * max(0, -stride))
            rot["Thigh" + side] = (angle, turn * stride * 14, lateral * wave * sign * 23)
            rot["Knee" + side] = (knee, 0, 0)
            rot["Foot" + side] = (-angle - knee - max(0, -stride) * 17, 0, -lateral * wave * sign * 15)
            rot["Toe" + side] = (12 * max(0, -stride), 0, 0)
            rot["Arm" + side] = (-angle * (0.95 if run else 0.7), 0, sign * (8 if run else 4))
            rot["Elbow" + side] = ((58 if run else 16) - stride * (16 if run else 8), 0, 0)
    elif clip in {"sit", "sit_down", "stand_up", "drive", "ride", "type"}:
        weight = u if clip == "sit_down" else 1 - u if clip == "stand_up" else 1
        weight = weight * weight * (3 - 2 * weight)
        shift = [0, -0.435 * weight, 0.025 * weight]
        rot["Spine"] = (-7 * weight - 17 * sin(pi * weight), 0, 0)
        for side, sign in (("L", 1), ("R", -1)):
            rot["Thigh" + side] = (86 * weight, 0, sign * 3 * weight)
            rot["Knee" + side] = (-91 * weight, 0, 0)
            rot["Foot" + side] = (5 * weight, 0, 0)
            reaching = clip in {"drive", "type"}
            rot["Arm" + side] = ((51 if reaching else 17) * weight, sign * 9 * weight, 0)
            rot["Elbow" + side] = ((36 if reaching else 40) * weight + (4 * sign * wave if reaching else 0), 0, -sign * 5)
            if clip == "type": rot["Hand" + side] = (sign * wave * 13, 0, 0)
        rot["Head"] = (-8 if clip == "type" else 2, wave * 3 * weight, 0)
    elif clip in {"search", "bandage", "crouch"}:
        shift = [0.02 * wave, -0.39, 0.06]
        rot["Spine"] = (-21 + wave * 3, 0, 0)
        rot["Head"] = (-13, wave * 8, 0)
        for side, sign in (("L", 1), ("R", -1)):
            rot["Thigh" + side] = (61 + 8 * sign, 0, sign * 8)
            rot["Knee" + side] = (-100 - 9 * sign, 0, 0)
            rot["Foot" + side] = (37, 0, 0)
            rot["Arm" + side] = (42 + sign * wave * 14, sign * 8, -sign * 11)
            rot["Elbow" + side] = (35 + sign * wave * (20 if clip == "bandage" else 12), 0, -sign * 10)
    elif clip in {"interact", "read", "speak", "torch"}:
        reach = sin(pi * u)**1.3 if clip == "interact" else 1
        rot["Chest"] = (-5 * reach, 7 * reach, 0)
        rot["Head"] = ((-19 if clip == "read" else -4) * reach, -4, 0)
        rot["ArmR"] = ((59 if clip in {"interact", "torch"} else 34) * reach, 3, 4)
        rot["ElbowR"] = ((20 if clip in {"interact", "torch"} else 99) * reach, 0, 15 * reach)
        if clip == "read":
            rot["ArmL"] = (31, -5, -3)
            rot["ElbowL"] = (87 + 3 * wave, 0, -14)
        if clip == "speak": rot["Head"] = (-3 + 3 * wave, 9 * breath, 0)
    elif clip in {"vault", "fall"}:
        rise = sin(pi * u) if clip == "vault" else 1
        shift[1] += 0.25 * rise if clip == "vault" else 0
        rot.update(Spine=(-24 * rise, 9 * rise, 0), ThighL=(78 * rise, 0, 0), KneeL=(-96 * rise, 0, 0),
                   ThighR=(32 * rise, 0, 0), KneeR=(-65 * rise, 0, 0), ArmL=(46 * rise, 0, 30 * rise),
                   ArmR=(55 * rise, 0, -32 * rise))
    elif clip in {"collapse", "down"}:
        w = 1 if clip == "down" else u * u * (3 - 2 * u)
        shift = [0, -0.79 * w, 0.18 * w]
        rot.update(Hips=(83 * w, 0, 14 * w), Spine=(8 * w, -9 * w, 0), Head=(-8 * w, 18 * w, 0),
                   ArmL=(13 * w, 0, 42 * w), ArmR=(23 * w, 0, -27 * w),
                   ThighR=(17 * w, 0, -12 * w), KneeR=(-37 * w, 0, 0))
    return shift, rot
