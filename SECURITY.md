# Política de seguridad

Arcadia Tranche Protocol protege accounting multi-tranche, distribución de
rendimiento, absorción de pérdidas, redenciones y emergency unwind.

## Alcance

El sistema dentro de alcance incluye todos los contratos bajo `src/`:

- accounting del tranche vault;
- recibos ERC-20 de shares;
- matemáticas de waterfall para pérdidas y harvests;
- configuración del risk oracle;
- vistas del strategy adapter;
- modelos read-only de lens y monitor.

Artifacts generados, archivos de caché local y dependencias vendorizadas quedan
fuera salvo que el código de Arcadia use una dependencia de forma incorrecta.

## Invariantes esperadas

- Los activos contabilizados totales igualan la suma de los tres tranche books
  cuando no hay report pendiente.
- Las pérdidas se asignan primero a junior, después mezzanine y finalmente
  senior.
- Los harvests se asignan primero a senior target, después mezzanine target y
  finalmente junior residual.
- Las redenciones de emergencia usan liquidation pricing y no incluyen soporte
  crediticio entre tranches.
- Las redenciones estándar deben estar cubiertas por underlying líquido.
- Las operaciones protegidas por rol solo pueden ejecutarse por el holder
  configurado o governor.

## Validación local

```bash
forge fmt --check
forge build --sizes
forge test
FOUNDRY_PROFILE=ci forge test -vvv
```

## Reporte responsable

Los reportes deben incluir:

- contrato y función afectados;
- secuencia exacta de transacciones;
- estado contable esperado y observado;
- impacto económico;
- propuesta de mitigación;
- supuestos sobre roles, timing o comportamiento del token.

No incluyas claves privadas, credenciales ni datos de terceros.
