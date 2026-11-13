# Versión personal %VERSION% (compilación %BUILD%)

### Mezclador por app — vista previa

- Actívalo en Ajustes → Audio y pasa el cursor sobre los títulos de volumen o micrófono para abrir el panel lateral. La preferencia se guarda y está desactivada de forma predeterminada.
- Ganancia independiente de 0–100%, silencio, iconos y nombres completos al pasar el cursor. El 100% conserva la señal original sin cambiar el volumen del dispositivo.
- Restablecer devuelve todas las apps al 100% y activa su sonido sin desactivar el mezclador. Las apps del micrófono solo se muestran. Las pausas conservan el nivel; un cambio de ruta/formato libera el procesamiento, con reintento si falla la limpieza.

### Correcciones y límites

- Corrige estados de carga tras desenchufar, duplicados Bluetooth, atribución de baterías, correspondencias AirPods y reapertura al segundo clic del Dock.
- Requiere macOS 14.2+ y permiso de captura de audio del sistema en el primer ajuste real. Abrir o pasar el cursor no captura audio; no se guarda ni sube audio.
- Solo salidas estéreo individuales validadas sin entradas físicas. Rutas bidireccionales, agregadas y múltiples no compatibles. Audio, permisos y AirPods necesitan validación real; cierra FineTune y otros mezcladores antes de probar.
- Mantiene macOS 13 y la interfaz personal; el mezclador no está disponible en sistemas antiguos.
