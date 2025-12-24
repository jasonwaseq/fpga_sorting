#!/usr/bin/env python3
"""
Interactive FPGA Radix Sorter Hardware Test

This script allows users to input numbers (0-1023) to be sorted by the FPGA.
It communicates via UART using the custom protocol:
  - 2-byte little-endian length header
  - Payload: 10-bit values as pairs of bytes (low byte, then high byte in bits [1:0])
"""

import serial
import sys
import time
import argparse
from typing import List, Tuple


class FPGASorterTester:
    def __init__(self, port: str, baudrate: int = 115200, timeout: float = 5.0):
        """Initialize FPGA sorter tester"""
        self.port = port
        self.baudrate = baudrate
        self.timeout = timeout
        self.ser = None

    def connect(self) -> bool:
        """Open serial connection"""
        try:
            self.ser = serial.Serial(self.port, self.baudrate, timeout=self.timeout)
            print(f"✅ Connected to {self.port} at {self.baudrate} baud")
            time.sleep(0.5)  # Wait for device to be ready
            return True
        except serial.SerialException as e:
            print(f"❌ Failed to open {self.port}: {e}")
            return False

    def disconnect(self):
        """Close serial connection"""
        if self.ser:
            self.ser.close()

    def encode_value(self, val: int) -> Tuple[int, int]:
        """Encode 10-bit value as two bytes: (low_byte, high_byte_with_2bits)"""
        if not (0 <= val <= 1023):
            raise ValueError(f"Value {val} out of range [0, 1023]")
        low_byte = val & 0xFF
        high_byte = (val >> 8) & 0x03
        return (low_byte, high_byte)

    def decode_value(self, low_byte: int, high_byte: int) -> int:
        """Decode two bytes back to 10-bit value"""
        return (high_byte << 8) | low_byte

    def send_sort_request(self, values: List[int]) -> bool:
        """Send sort request to FPGA"""
        n = len(values)
        if n > 65535:
            print(f"❌ Too many values: {n} (max 65535)")
            return False

        # Build packet
        packet = bytearray()

        # Length header (little-endian)
        packet.append(n & 0xFF)
        packet.append((n >> 8) & 0xFF)

        # Payload values
        for val in values:
            low, high = self.encode_value(val)
            packet.append(low)
            packet.append(high)

        # Send
        try:
            self.ser.write(packet)
            self.ser.flush()
            return True
        except serial.SerialException as e:
            print(f"❌ Failed to send: {e}")
            return False

    def receive_sorted_values(self, n: int) -> List[int] or None:
        """Receive sorted values from FPGA"""
        expected_bytes = 2 + n * 2  # header + payload
        received = bytearray()

        deadline = time.time() + self.timeout
        while len(received) < expected_bytes and time.time() < deadline:
            chunk = self.ser.read(expected_bytes - len(received))
            if chunk:
                received.extend(chunk)
            else:
                time.sleep(0.01)

        if len(received) < expected_bytes:
            print(
                f"❌ Incomplete response: got {len(received)} bytes, expected {expected_bytes}"
            )
            return None

        # Verify header
        header_len = received[0] | (received[1] << 8)
        if header_len != n:
            print(
                f"❌ Length mismatch: header says {header_len}, expected {n}"
            )
            return None

        # Decode values
        values = []
        for i in range(n):
            low = received[2 + i * 2]
            high = received[2 + i * 2 + 1] & 0x03
            val = self.decode_value(low, high)
            values.append(val)

        return values

    def test_sort(self, values: List[int]) -> bool:
        """Test sorting of given values"""
        print(f"\n{'='*70}")
        print(f"Sorting {len(values)} values...")
        print(f"{'='*70}")

        # Display input
        print(f"Input:  {values}")

        # Send to FPGA
        if not self.send_sort_request(values):
            return False

        # Receive result
        sorted_values = self.receive_sorted_values(len(values))
        if sorted_values is None:
            return False

        # Display result
        print(f"Output: {sorted_values}")

        # Verify correctness
        expected = sorted(values)
        if sorted_values == expected:
            print(f"✅ PASS - Values are correctly sorted!")
            return True
        else:
            print(f"❌ FAIL - Expected: {expected}")
            return False


def get_user_input() -> List[int]:
    """Get numbers from user input"""
    while True:
        try:
            print(
                "\nEnter numbers to sort (space-separated, 0-1023), or 'quit' to exit:"
            )
            user_input = input("> ").strip()

            if user_input.lower() in ["quit", "exit", "q"]:
                return None

            if not user_input:
                print("Please enter at least one number")
                continue

            values = [int(x) for x in user_input.split()]

            # Validate
            for val in values:
                if not (0 <= val <= 1023):
                    print(
                        f"❌ Value {val} out of range [0, 1023]"
                    )
                    raise ValueError()

            if len(values) > 256:
                print(f"⚠️  Warning: {len(values)} values (recommendation: ≤256)")
                confirm = input("Continue? (y/n): ").strip().lower()
                if confirm != "y":
                    continue

            return values

        except ValueError:
            print("❌ Invalid input. Please enter numbers separated by spaces.")


def main():
    parser = argparse.ArgumentParser(
        description="Interactive FPGA Radix Sorter Test"
    )
    parser.add_argument(
        "port", help="Serial port (e.g., /dev/ttyUSB0 or COM3)"
    )
    parser.add_argument(
        "--baudrate",
        type=int,
        default=115200,
        help="Baud rate (default: 115200)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=5.0,
        help="Timeout in seconds (default: 5.0)",
    )
    parser.add_argument(
        "--test",
        action="store_true",
        help="Run built-in tests instead of interactive mode",
    )

    args = parser.parse_args()

    tester = FPGASorterTester(args.port, args.baudrate, args.timeout)

    if not tester.connect():
        sys.exit(1)

    try:
        if args.test:
            # Built-in test cases
            test_cases = [
                [5, 4, 1],
                [10, 20, 5, 15, 1],
                [1023, 0, 512, 256],
                [100, 100, 100],
                [42],
                [],
                list(range(0, 100, 5)),
            ]

            passed = 0
            for values in test_cases:
                if tester.test_sort(values):
                    passed += 1

            print(f"\n{'='*70}")
            print(f"Test Results: {passed}/{len(test_cases)} passed")
            print(f"{'='*70}")

            if passed == len(test_cases):
                print("✅ All tests passed!")
            else:
                print(f"❌ {len(test_cases) - passed} test(s) failed")
                sys.exit(1)

        else:
            # Interactive mode
            print("\n" + "=" * 70)
            print("FPGA Radix Sorter - Interactive Test")
            print("=" * 70)
            print("Range: 0-1023 (10-bit values)")
            print("Max recommended: 256 values per sort")
            print("Type 'quit' to exit\n")

            while True:
                values = get_user_input()
                if values is None:
                    break

                tester.test_sort(values)

            print("\n✅ Goodbye!")

    finally:
        tester.disconnect()


if __name__ == "__main__":
    main()
