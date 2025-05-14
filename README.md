### Solana monitoring and tuning script


Full script with options to install and configure Solana monitoring, tuning scripts and firewall:
```bash
/bin/bash -c "$(curl -fsSL https://api.vano.one/solana-configs)"
```

Script  to install monitoring only:
```bash
/bin/bash -c "$(curl -fsSL https://api.vano.one/solana-monitoring)"
```

Script  to install status check with uptime kuma:
```bash
/bin/bash -c "$(curl -fsSL https://api.vano.one/solana-status-check)"
```



Long URLs are here:

Full script with options to install and configure Solana monitoring, tuning scripts and firewall
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.9/install_solana_metrics.sh)"
```

Script  to install monitoring only
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.9/install_solana_monitoring.sh)"
```

Script  to install status check with uptime kuma:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.9/install_status_check.sh)"
```


### Upgrade firedancer with version selection
```bash
# Latest version:
/bin/bash -c "$(curl -fsSL https://api.vano.one/fd-update)"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v3.12.0/firedancer_update.sh)"

# With specific version as an argument
/bin/bash -c "$(curl -fsSL https://api.vano.one/fd-update)" _ v0.503.20214
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v3.12.0/firedancer_update.sh)" _ v0.503.20214
```


### Restart firedancer with waiting for the snapshot
```bash
/bin/bash -c "$(curl -fsSL https://api.vano.one/fd-restart)"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v3.1/firedancer_restart.sh)"
```



### Firedancer/agave snapshot finder

```bash
/bin/bash -c "$(curl -fsSL https://api.vano.one/snapshot-finder)"
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v3.5.0/snapshot_finder.sh)"
```
