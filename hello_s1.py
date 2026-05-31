"""Drive the RoboMaster S1 forward 0.5 m, then stop.

Prerequisites:
- S1 and PC are joined to the same Wi-Fi network (S1 in station mode).
- `pip install -r requirements.txt`
- Run from a clear, flat area with at least 1 m of space ahead of the robot.
"""

from robomaster import robot


def main() -> None:
    ep_robot = robot.Robot()
    ep_robot.initialize(conn_type="sta")

    try:
        version = ep_robot.get_version()
        sn = ep_robot.get_sn()
        print(f"Connected to S1  sn={sn}  firmware={version}")

        ep_robot.chassis.move(x=0.5, y=0.0, z=0.0, xy_speed=0.5).wait_for_completed()
        print("Move complete.")
    finally:
        ep_robot.close()


if __name__ == "__main__":
    main()
