# Port of ycbtsdk ByteUtil.crc16_compute + YCBTClientImpl.sendData2Device
def crc16(data):
    s = 0xFFFF
    for b in data:
        s = ((s << 8) & 0xFF00) | ((s >> 8) & 0xFF)
        s ^= b
        s ^= (s & 0xFF) >> 4
        s ^= (s << 12) & 0xFFFF
        s ^= ((s & 0xFF) << 5) & 0xFFFF
    return s & 0xFFFF

def frame(group, key, payload=b""):
    total = len(payload) + 6
    body = bytes([group, key, total & 0xFF, (total >> 8) & 0xFF]) + bytes(payload)
    c = crc16(body)
    return body + bytes([c & 0xFF, (c >> 8) & 0xFF])

def hx(b): return " ".join(f"{x:02X}" for x in b)

if __name__ == "__main__":
    cmds = {
        "Info del dispositivo (bateria, firmware)": (0x02, 0x00, b"GC"),
        "Datos en vivo (pulso, SpO2, temp, pasos)": (0x02, 0x20, b""),
        "Temperatura actual":                     (0x02, 0x0E, b""),
        "SpO2 actual":                            (0x02, 0x11, b"IS"),
        "Historial de sueno":                     (0x05, 0x04, b""),
        "Historial de pulso":                     (0x05, 0x06, b""),
        "Historial completo (HRV, SpO2, temp)":   (0x05, 0x09, b""),
    }
    for name, (g, k, p) in cmds.items():
        print(f"{name:42s} {hx(frame(g,k,p))}")
