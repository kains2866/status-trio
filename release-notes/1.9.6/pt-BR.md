# Versão pessoal %VERSION% (compilação %BUILD%)

### Mixer por app — prévia

- Ative em Ajustes → Áudio e passe o cursor sobre os títulos de volume ou microfone para abrir o painel lateral. A preferência é salva e vem desativada.
- Ganho independente de 0–100%, silenciamento, ícones e nomes completos ao passar o cursor. 100% mantém o sinal original sem mudar o volume do dispositivo.
- Redefinir restaura todos os apps para 100% e remove o silenciamento mantendo o mixer ativo. Os apps do microfone são apenas listados. Pausas preservam o nível; mudanças de rota/formato liberam o processamento e falhas de limpeza permitem nova tentativa.

### Correções e limites

- Corrige estados de carga após desconectar, duplicatas Bluetooth, atribuição de bateria, correspondência AirPods e reabertura após o segundo clique no Dock.
- Mixer requer macOS 14.2+ e permissão de captura de áudio do sistema no primeiro ajuste real. Abrir ou passar o cursor não captura áudio; nada é salvo ou enviado.
- Apenas saídas estéreo únicas validadas sem fluxos físicos de entrada. Rotas bidirecionais, agregadas e múltiplas não são suportadas. Áudio, permissões e AirPods ainda exigem testes reais; feche FineTune e outros mixers antes do teste.
- Mantém macOS 13 e a interface pessoal; o mixer fica indisponível em sistemas antigos.
