# Sphere Light Reference (SLR)

Un plug-in di DT Hub: dispone fino a tre luci su una sfera, la calcola (ray tracing su CPU) e la manda a Draw Things per far
combaciare luce, colori e direzione del sole di un'immagine con quelli della sfera. Funziona con FLUX.2 Klein 9B e il LoRA
`flux_2_sun_direction_lora_v1_lora_f16.ckpt`.

- **Invia a Generazione:** la sfera va nel Moodboard e il pulsante Run diventa una pipeline di preset: `SLR · Match the sun`,
  preceduto da `SLR · Overcast` (appiattisce le ombre del canvas) se la casella «Overcast» è accesa.
- **Solo la sfera nel Moodboard:** manda solo l'immagine, per usare prompt e parametri tuoi.
- **I preset** si registrano da soli all'attivazione e stanno nel menu Preset: puoi cambiarli (il peso del LoRA, i passi…) e
  salvarli con lo stesso nome; il plug-in non li sovrascrive mai. Se ne cancelli uno, «Invia a Generazione» lo ricrea.
- **Salva anche sulla Scrivania:** una copia della sfera come `Sphere Light NNN.png`.

## Costruirlo

    Plugins/SphereLight/Scripts/build.sh OUT_FOLDER     # fa OUT_FOLDER/SphereLight.dthubplugin
    cd Plugins/SphereLight && swift test                # 30 test

Poi si aggiunge in DT Hub › Preferenze › Plug-in (si trascina il file) e si accende dal menu Plug-in dell'header.
Il codice del renderer viene dall'app `LightDirectionApp` (copia: l'app standalone non si sviluppa più).
