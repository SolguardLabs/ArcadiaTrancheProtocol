# Modelo económico

## Unidades y redondeo

Los valores monetarios usan los decimales del activo; los precios por share usan WAD (`1e18`) y
las proporciones usan bps (`10_000 = 100 %`). Las funciones de depósito y redención redondean hacia
abajo, por lo que el sistema no promete fracciones que no puede representar.

Para una tranche `i`:

```text
Pᵢ = Aᵢ × WAD / Sᵢ                 si Sᵢ > 0
S_mint = assets × WAD / P_entry
A_out = shares × P_exit / WAD
```

Si no existen shares, el precio base es `1 WAD`.

## Waterfall de rendimiento

Sea `H` el ingreso realizado y `f` la comisión en bps:

```text
fee       = H × f / 10_000
net       = H - fee
senior    = min(net, Aₛ × targetₛ / 10_000)
remaining = net - senior
mezzanine = min(remaining, Aₘ × targetₘ / 10_000)
junior    = remaining - mezzanine
```

Ejemplo con `Aₛ=1.000`, `Aₘ=500`, `Aⱼ=500`, targets de 4 % y 9 %, comisión 0 y
`H=150`:

| Destino | Cálculo | Importe |
| --- | --- | ---: |
| Senior | `min(150, 1.000 × 4 %)` | 40 |
| Mezzanine | `min(110, 500 × 9 %)` | 45 |
| Junior | `105 - 40 - 45` | 65 |

El book final es `1.040 / 545 / 565` y el total contabilizado asciende a `2.150`.

## Waterfall de pérdidas

Para una pérdida realizada `L`:

```text
Lⱼ = min(L, Aⱼ)
Lₘ = min(L - Lⱼ, Aₘ)
Lₛ = min(L - Lⱼ - Lₘ, Aₛ)
Lᵤ = L - Lⱼ - Lₘ - Lₛ
```

Una pérdida de 700 sobre books `1.000 / 500 / 500` asigna 500 a Junior, 200 a Mezzanine y 0 a
Senior. `Lᵤ` solo es distinto de cero si la pérdida informada supera el capital total.

## Precio protegido y precio de liquidación

La operación normal puede calcular un precio protegido limitado por `maxProtectionBps`:

```text
protection = min(residualCredit, trancheAssets × maxProtectionBps / 10_000)
P_protected = (trancheAssets + protection) × WAD / trancheShares
```

En emergencia, `liquidationPrice` usa exclusivamente activos y shares de la tranche. Los paneles
deben mostrar por separado precio de entrada, salida y liquidación.

## Cobertura

La cobertura Senior se expresa como capital subordinado sobre capital Senior:

```text
coverageSeniorBps = (Aₘ + Aⱼ) × 10_000 / Aₛ
```

Con `1.000 / 500 / 500`, la cobertura es 10.000 bps. Tras una pérdida de 700, queda en 3.000 bps.
Las bandas del oracle y del parameter store permiten diferenciar estado normal, advertencia y
crítico.

## Score de escenarios

El motor calcula:

```text
score = (lossBps × 3.500
       + liquidityHaircutBps × 2.500
       + correlationBps × 2.000
       + concentrationBps × 2.000) / 10.000
```

| Score | Nivel |
| ---: | --- |
| `< 2.000` | Core |
| `2.000 – 4.499` | Standard |
| `4.500 – 6.999` | Elevated |
| `≥ 7.000` | Restricted |

La pérdida Senior fuerza `Restricted`. La solvencia del escenario requiere simultáneamente que no
quede pérdida sin asignar y que la liquidez estresada cubra el buffer mínimo.

## Reconciliación mínima

Después de cada harvest, reporte, cierre o salida masiva se debe verificar:

```text
totalAccountedAssets = Aₛ + Aₘ + Aⱼ
balance(vault) + liquidAssets(strategy) ≥ obligación líquida del intervalo
checkpoint.stateDigest = currentStateDigest() en el instante aprobado
```

Las diferencias deben detener nuevas asignaciones hasta identificar su origen.
