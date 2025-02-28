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
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.5/install_solana_metrics.sh)"
```

Script  to install monitoring only
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.5/install_solana_monitoring.sh)"
```

Script  to install status check with uptime kuma:
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.6/install_status_check.sh)"
```


### Upgrade firedancer with version selection
```bash
/bin/bash -c "$(curl -fsSL https://api.vano.one/fd-update)" _ v0.404.20113
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ivan-leschinsky/solana-configs/v2.7/firedancer_update.sh)" _ v0.404.20113
```
