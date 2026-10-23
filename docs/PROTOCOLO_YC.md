# Protocolo Bluetooth de la pulsera SOOP 3846 (SDK Yucheng "ycbtsdk")

Fuente: descompilación de HealthWear 1.1.92 para Android (`com.yucheng.HealthWear`),
clases `com.yucheng.ycbtsdk.core.CMD`, `YCBTClientImpl`, `DataUnpack`, `gatt.BleHelper`.

## Canal

| Rol | UUID | Uso |
|---|---|---|
| Servicio | `BE940000-7333-BE46-B7AE-689E71722BD5` | Canal de comandos del fabricante |
| Comandos + respuestas | `BE940001-…` | La app escribe aquí **y activa Indicate aquí mismo**: en esta pulsera las respuestas llegan por BE940001 (verificado: `02 03 0B 00 'SOOP\0' FE 23`) |
| Escritura 2 | `BE940002-…` | Solo para OTA / bloques grandes |
| Avisos | `BE940003-…` | Indicate: avisos espontáneos (ej. `06 00` pasos en vivo) |
| Pulso estándar | `180D` / `2A37` | Pulso en vivo (no requiere comandos) |
| Podómetro | `FEE7` / `FEA1` | Pasos/distancia/kcal del día (lectura directa) |

El servicio Nordic UART (`6E400001…`) **no se usa**: el SDK ignora sus notificaciones.
MTU solicitado: 185 (si llega un paquete de MTU-3 bytes, se concatena con el siguiente).

## Formato del paquete (igual en ambos sentidos)

```
[grupo] [comando] [largo_lo] [largo_hi] [datos ...] [crc_lo] [crc_hi]
```
- `largo` = longitud TOTAL del paquete (datos + 6), little-endian.
- CRC16 Nordic (`crc16_compute`, init 0xFFFF) sobre todo lo anterior al CRC.
- Respuesta de error: datos de 1 byte `0xFB` (cmd no soportado), `0xFC` (key), `0xFD` (largo), `0xFE` (datos), `0xFF` (CRC).

Grupos: 1 Ajustes · 2 Consultas · 3 Control app · 4 Control dispositivo · 5 Historial · 6 Tiempo real.

## Comandos útiles para Phoop

| Acción | Paquete (hex) | Respuesta |
|---|---|---|
| Info dispositivo | `02 00 08 00 47 43 6F EC` | datos[4]=estado carga, datos[5]=**batería %**, datos[2..3]=firmware |
| Datos en vivo | `02 20 06 00 C8 45` | ver "Datos en vivo" |
| Temperatura actual | `02 0E 06 00 0F D8` | `entero.decimal` °C |
| SpO₂ actual | `02 11 08 00 49 53 5A 73` | [enMedición, valor%] |
| Historial sueño | `05 04 06 00 E3 4E` | ver "Historial" |
| Historial pulso | `05 06 06 00 83 20` | registros de 6 bytes |
| Historial completo | `05 09 06 00 B2 0C` | registros de 20 bytes (**HRV**, SpO₂, temp, resp.) |
| Poner hora | `01 00 0E 00 <año_lo año_hi mes día hora min seg diaSemana> crc` | diaSemana: 0=lunes … 6=domingo |
| Monitoreo de pulso | grupo 1, cmd `0x0C`, datos `[1=on, intervalo_min]` | |
| Monitoreo HRV | grupo 1, cmd `0x45`, 5 bytes de configuración | |

Phoop **no debe** enviar los comandos de borrado (grupo 5, cmd `0x40`–`0x52`).

## Datos en vivo (respuesta a `02 20`)
`[pulso, sistólica, diastólica, SpO₂, respiración, temp_ent, temp_dec, pasos(3B), kcal(2B), distancia_m(2B), …]`

## Historial (grupo 5)

1. App envía `05 <tipo> 06 00 crc`.
2. Pulsera responde con cabecera `05 <tipo>`: `[nRegistros(2B), nPaquetes(4B), nBytes(4B)]`.
3. Llegan paquetes de datos `05 <tipo+15>` (ej. sueño 0x13, pulso 0x15, completo 0x18): se concatenan los datos.
4. Llega `05 80`: `[nPaquetes(2B), nBytes(2B), crc(2B)]` → se verifica el CRC16 de los datos unidos.
5. App confirma con `05 80 07 00 00 F3 6A` (OK) o con datos `04` (error).

Tiempos: segundos desde **2000-01-01 en hora local** (sumar 946684800 → epoch y restar el offset de zona horaria).

### Sueño (`0x04`), bloque por noche
| Bytes | Campo |
|---|---|
| 0–1 | marca |
| 2–3 | largo del bloque |
| 4–7 | inicio |
| 8–11 | fin |
| 12–13 | nº profundo (si es `FFFF`, formato nuevo en segundos) |
| 14–15 | nº ligero / REM total |
| 16–17 | profundo total (min, o s si formato nuevo) |
| 18–19 | ligero total |
| 20… | tramos de 8 bytes: `[fase, inicio(4B), duración_s(3B)]` |

Fases: **241 profundo · 242 ligero · 243 REM · 244 despierto**.

### Pulso (`0x06`), registros de 6 bytes
`[tiempo(4B), modo, pulso]`

### Completo (`0x09`), registros de 20 bytes
| Byte | Campo |
|---|---|
| 0–3 | tiempo |
| 4–5 | pasos |
| 6 | pulso |
| 7 / 8 | sistólica / diastólica (estimada) |
| 9 | SpO₂ % |
| 10 | respiración (rpm) |
| 11 | **HRV (ms)** |
| 12 | CVRR |
| 13 / 14 | temperatura entero / decimal |
| 15 / 16 | grasa corporal |
| 17 | glucosa (estimada) |

## Notas
- HealthWear borra el historial de la pulsera tras sincronizar. Si se usan ambas apps,
  Phoop solo verá lo que HealthWear aún no haya descargado.
- Pasos/kcal/distancia validados: `FEA1` = `07 1F0400 410300 210000` → 1055 pasos, 833 m, 33 kcal
  (coincide con HealthWear).
