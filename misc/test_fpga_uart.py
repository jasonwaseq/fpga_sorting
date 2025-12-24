#!/usr/bin/env python3
"""
Test UART communication with FPGA radix sorter.
Usage: python3 test_fpga_uart.py /dev/ttyUSBX
"""
import serial
import sys
import time
import argparse

def encode_value(val):
    """Encode a 10-bit value as 2 bytes (little-endian)."""
    low_byte = val & 0xFF
    high_byte = (val >> 8) & 0x03
    return bytes([low_byte, high_byte])

def decode_value(low, high):
    """Decode a 10-bit value from 2 bytes."""
    return (high & 0x03) << 8 | low

def test_sort(ser, values, test_name, pace_ms=0):
    """Send values to FPGA, receive sorted output, and verify."""
    print(f"\n{'='*70}")
    print(f"TEST: {test_name}")
    print(f"{'='*70}")
    
    # Prepare payload
    length = len(values)
    payload = length.to_bytes(2, byteorder='little')
    
    if pace_ms and pace_ms > 0:
        # Send length first; stream values one by one with pacing
        ser.reset_input_buffer(); ser.reset_output_buffer()
        ser.write(payload)
        ser.flush()
        for val in values:
            b = encode_value(val)
            ser.write(b)
            ser.flush()
            time.sleep(pace_ms/1000.0)
    else:
        for val in values:
            payload += encode_value(val)
    
    print(f"Input values: {values}")
    print(f"Sending {len(payload)} bytes: {payload.hex()}")
    
    if not (pace_ms and pace_ms > 0):
        # Clear any pending data
        ser.reset_input_buffer()
        ser.reset_output_buffer()
        
        # Send data and start timing
        start_time = time.perf_counter()
        ser.write(payload)
        ser.flush()
    else:
        start_time = time.perf_counter()
    
    # Read response length
    resp_len_bytes = ser.read(2)
    
    if len(resp_len_bytes) < 2:
        print(f"❌ ERROR: No length response (got {len(resp_len_bytes)} bytes)")
        return False
    
    out_len = int.from_bytes(resp_len_bytes, byteorder='little')
    print(f"Output length: {out_len}")
    
    if out_len != length:
        print(f"❌ ERROR: Length mismatch! Expected {length}, got {out_len}")
        return False
    
    # Read all value bytes
    expected_bytes = out_len * 2
    # Read robustly until we have all bytes or hit a time limit
    rx_chunks = bytearray()
    read_start = time.time()
    while len(rx_chunks) < expected_bytes and (time.time() - read_start) < 5.0:
        need = expected_bytes - len(rx_chunks)
        chunk = ser.read(need)
        if chunk:
            rx_chunks.extend(chunk)
        else:
            # Give FPGA time to produce next bytes
            time.sleep(0.01)
    rx_data = bytes(rx_chunks)
    
    elapsed_time = time.perf_counter() - start_time
    
    if len(rx_data) < expected_bytes:
        print(f"❌ ERROR: Incomplete data (got {len(rx_data)}/{expected_bytes} bytes)")
        print(f"Received: {rx_data.hex() if rx_data else 'NOTHING'}")
        return False
    
    print(f"Received {len(rx_data)} bytes: {rx_data.hex()}")
    print(f"⏱️  Sort time: {elapsed_time*1000:.2f} ms ({len(values)} values)")
    
    # Decode values
    output_values = []
    for i in range(0, len(rx_data), 2):
        val = decode_value(rx_data[i], rx_data[i+1])
        output_values.append(val)
    
    print(f"Output values: {output_values}")
    
    # Verify sorted
    expected = sorted(values)
    print(f"Expected:      {expected}")
    
    if output_values == expected:
        print("✅ PASS - Values are correctly sorted!")
        return True
    else:
        print("❌ FAIL - Output does not match expected sorted values!")
        return False

def main():
    parser = argparse.ArgumentParser(description="FPGA UART radix sorter test")
    parser.add_argument("port", help="Serial port, e.g., /dev/ttyUSB0")
    parser.add_argument("--timeout", type=float, default=5.0, help="Serial read timeout (seconds)")
    parser.add_argument("--pace-ms", type=int, default=0, help="Pacing delay (ms) between sending each value pair")
    args = parser.parse_args()
    
    port = args.port
    
    try:
        print(f"Opening serial port {port} at 115200 baud...")
        ser = serial.Serial(port, baudrate=115200, timeout=args.timeout)
        print(f"✅ Serial port opened successfully")
        time.sleep(0.5)  # Let FPGA settle
        
    except serial.SerialException as e:
        print(f"❌ ERROR: Could not open serial port: {e}")
        sys.exit(1)
    
    # Run test cases
    test_results = []
    
    # Test 1: Single value
    test_results.append(test_sort(ser, [42], "Single value (42)", pace_ms=args.pace_ms))
    time.sleep(0.2)
    
    # Test 2: Already sorted
    test_results.append(test_sort(ser, [1, 2, 3, 4, 5], "Already sorted", pace_ms=args.pace_ms))
    time.sleep(0.2)
    
    # Test 3: Reverse sorted
    test_results.append(test_sort(ser, [5, 4, 3, 2, 1], "Reverse sorted", pace_ms=args.pace_ms))
    time.sleep(0.2)
    
    # Test 4: Random order
    test_results.append(test_sort(ser, [15, 3, 27, 8, 19], "Random order", pace_ms=args.pace_ms))
    time.sleep(0.2)
    
    # Test 5: Duplicates
    test_results.append(test_sort(ser, [5, 2, 5, 1, 5, 2], "Duplicates", pace_ms=args.pace_ms))
    time.sleep(0.2)
    
    # Test 6: Max 10-bit values
    test_results.append(test_sort(ser, [1023, 0, 511, 256], "Max 10-bit values", pace_ms=args.pace_ms))
    time.sleep(0.2)
    
    # Test 7: All same
    test_results.append(test_sort(ser, [100, 100, 100], "All same value", pace_ms=args.pace_ms))
    time.sleep(0.2)
    
    # Test 8: Empty (edge case)
    test_results.append(test_sort(ser, [], "Empty dataset", pace_ms=args.pace_ms))
    time.sleep(0.2)
    
    # Test 9: Large dataset
    import random
    random.seed(12345)
    large_data = [random.randint(0, 1023) for _ in range(50)]
    test_results.append(test_sort(ser, large_data, "Large dataset (50 values)", pace_ms=args.pace_ms))
    
    ser.close()
    
    # Summary
    print(f"\n{'='*70}")
    print(f"TEST SUMMARY")
    print(f"{'='*70}")
    passed = sum(test_results)
    total = len(test_results)
    print(f"Passed: {passed}/{total}")
    
    if passed == total:
        print("🎉 ALL TESTS PASSED!")
        sys.exit(0)
    else:
        print(f"⚠️  {total - passed} TEST(S) FAILED")
        sys.exit(1)

if __name__ == "__main__":
    main()
