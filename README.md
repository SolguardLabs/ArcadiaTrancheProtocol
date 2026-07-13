# Arcadia Tranche Protocol

![banner](./assets/banner.png)

Arcadia Tranche Protocol es una implementación Solidity/Foundry de un vault
multi-tranche. Los depositantes pueden seleccionar exposición senior, mezzanine
o junior, recibir recibos ERC-20 y participar en una waterfall de rendimiento
con absorción de pérdidas ordenada por prioridad de tranche.

Los contratos separan accounting de vault, tokens de shares, matemáticas de
waterfall, oráculo de riesgo, vistas operativas, monitorización y estrategia de
buffer.

## Arquitectura

```text
                    +--------------------+
                    | ArcadiaRiskOracle  |
                    +----------+---------+
                               |
+---------------+     +--------v---------+      +-------------------+
| Share Tokens  |<----| ArcadiaTranche   |----->| ArcadiaLens       |
| aSEN/aMEZ/aJUN|     | Vault            |      | ArcadiaMonitor    |
+---------------+     +---+----------+---+      +-------------------+
                           |          |
                           |          v
                           |   ArcadiaBufferedStrategy
                           v
                     Underlying ERC-20
```

- `ArcadiaTrancheVault` gestiona depósitos, redenciones, harvest allocation,
  loss reports, pausa y emergency unwind.
- `TrancheShareToken` es el recibo ERC-20 de cada tranche.
- `WaterfallMath` y `FixedPointMath` aíslan cálculos deterministas de
  accounting.
- `ArcadiaRiskOracle` almacena bandas de riesgo y metadata de observación.
- `ArcadiaLens` agrega vistas de protocolo y cuenta para frontends.
- `ArcadiaMonitor` expone health checks para keepers.
- `ArcadiaBufferedStrategy` es un adapter local para flujos de despliegue y
  pruebas.

## Tranches

| Tranche | Posición | Tratamiento de rendimiento | Tratamiento de pérdidas |
| --- | --- | --- | --- |
| Senior | Mayor prioridad | Recibe target yield primero | Última en absorber pérdidas |
| Mezzanine | Prioridad media | Recibe yield tras senior target | Absorbe pérdidas tras junior |
| Junior | First-loss capital | Recibe yield residual | Primera en absorber pérdidas |

Las shares se valoran desde el estado contable de cada tranche. Las redenciones
usan el exit price vigente expuesto por el vault, mientras que las redenciones
de emergencia usan pricing de liquidación basado en el book de cada tranche.

## Flujo operativo

1. Los usuarios aprueban el activo subyacente y llaman
   `deposit(tranche, assets, receiver)`.
2. El vault mintea shares de tranche usando el entry price correspondiente.
3. Los keepers llaman `harvest(amount, sourceHash)` tras rendimiento realizado.
4. El rendimiento se distribuye primero a senior target, luego mezzanine target
   y finalmente junior residual.
5. Reporters autorizados llaman `reportLoss(amount, reasonHash)` para registrar
   pérdidas realizadas.
6. Los keepers liquidan reports pendientes tras reconciliación.
7. Los usuarios llaman `redeem(tranche, shares, receiver, owner)` durante
   operación estándar.
8. Guardians pueden activar emergency mode y los usuarios pueden salir con
   liquidation pricing.

## Seguridad y controles

Los roles están separados en governor, keeper, reporter, guardian, strategist y
risk manager. Los contratos asumen comportamiento ERC-20 estándar del activo
subyacente y no soportan activos con fee-on-transfer.

Consulta [SECURITY.md](./SECURITY.md) para invariantes, alcance y reporte
responsable.

## Requisitos

- Foundry `1.7.1` o superior.
- Solidity `0.8.24`.

## Quick start

```bash
forge build
forge test
```

CI local:

```bash
bash scripts/ci.sh
```

Test focalizado:

```bash
bash scripts/tests.sh --match-path tests/integration/HarvestAndLoss.t.sol
```

## Comandos

```bash
forge fmt --check
forge build --sizes
forge test
FOUNDRY_PROFILE=ci forge test -vvv
```

## Licencia

MIT.
