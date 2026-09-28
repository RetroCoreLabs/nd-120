# TTL 74139

The 74139 is a Dual 1-of-4 Decoder/Demultiplexer, often used in digital circuits.

It has two identical and independent 1-of-4 decoders. Each decoder has two select inputs (A, B), ONE active low enable input (/G), and four active low outputs (/Y0, /Y1, /Y2, /Y3). In `TTL_74139.v` the enable of decoder 1 is `G1_n` and the enable of decoder 2 is `G2_n`. Datasheet: the TI SN54LS139A link in the header of `TTL_74139.v`.

## Test program verification

![Screenshot from GTKWave](gtkwave.png)


## Truth Table (one decoder)

| /G | B  | A  | /Y0 | /Y1 | /Y2 | /Y3 |
|----|----|----|-----|-----|-----|-----|
|  1 |  X |  X |  1  |  1  |  1  |  1  |
|  0 |  0 |  0 |  0  |  1  |  1  |  1  |
|  0 |  0 |  1 |  1  |  0  |  1  |  1  |
|  0 |  1 |  0 |  1  |  1  |  0  |  1  |
|  0 |  1 |  1 |  1  |  1  |  1  |  0  |

## Explanation

/G is the enable input (active low). When /G is high, all four outputs of that decoder are high (1), regardless of A and B.
When /G is low, the outputs are determined by the select inputs A and B.
A and B are select inputs. They determine which one of the four outputs (/Y0, /Y1, /Y2, /Y3) is low (0).
/Y0, /Y1, /Y2, /Y3 are the active low outputs. Only one of them is low at a time.

## Select Inputs (B, A) to Output Mapping

B is the high bit, A the low bit:

B=0 A=0 -> /Y0
B=0 A=1 -> /Y1
B=1 A=0 -> /Y2
B=1 A=1 -> /Y3
