# Log tags: без квадратных скобок

## Откуда взялась «опечатка-эпидемия `[h` → »»

В **git-файлах** префиксы вроде `[host]` / `[hardening]` обычно были **целыми** (байты `5b 68 6f 73 74 5d` = `[host]`).

Ложные «опечатки» (`ost]`, `ardening]`, `ulti-wan]`) возникают при **чтении/правке через PowerShell или regex без экранирования**:

| Инструмент | Что делает `[host]` |
|------------|---------------------|
| PowerShell `-replace "[host]", ""` / `-match` | character class `h\|o\|s\|t` → вырезает буквы |
| PowerShell double-quoted / type syntax | `[host]` как type accelerator → parse error / искажение команды |
| Markdown (отчёт аудита без code fence) | reference link `[host]` |
| Console wrap | визуально ломает `info "[h` / `ost]"` на границе строки |

Репро: `re.sub(r"[host]", "", 'info "[hardening] done"')` → `'inf "[ardening] dne"'`.

Это **не** sed в `Publish-GithubOrphan` и не silent hook в репо.

## Формат логов (обязательно)

```bash
info "host: hostname=$hn"
warn "nat-firewall: flush"
```

Запрещено: `info "[host] …"`.

Проверка перед коммитом/релизом:

```bash
python3 scripts/ci/check_log_tags.py
```

Миграция: `python3 scripts/ci/rewrite_log_tags.py`
