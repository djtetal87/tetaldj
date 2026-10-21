import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sidedeck/engine/usb_output.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart' show MidiDevice;
import 'package:sidedeck/midi/midi_controller.dart';
import 'package:sidedeck/state/dj_controller.dart';

import 'package:sidedeck/subsonic/subsonic_client.dart';
import 'package:sidedeck/theme/sidedeck_theme.dart';

/// Shown in Ajustes; bump with pubspec.yaml.
const kAppVersion = '0.5.0';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.dj, this.midi});

  final DjController dj;
  final MidiController? midi;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _url.text = prefs.getString('subsonic_url') ?? '';
    _user.text = prefs.getString('subsonic_user') ?? '';
    _pass.text = prefs.getString('subsonic_pass') ?? '';
    setState(() {});
  }

  Future<void> _saveAndTest() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await SubsonicClient.savePrefs(
        url: _url.text.trim(),
        user: _user.text.trim(),
        pass: _pass.text,
      );
      final client = SubsonicClient(
        baseUrl: _url.text.trim(),
        username: _user.text.trim(),
        password: _pass.text,
      );
      await client.ping();
      setState(() => _status = 'Connected OK');
    } catch (e) {
      setState(() => _status = 'Failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.midi != null) ...[_midiSection(widget.midi!), const SizedBox(height: 24)],
          const Text(
            'External mixer',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Turn this on with a USB mixer plugged into the phone. Deck A and Deck B '
            'go out as separate channels so you mix and cue on the hardware — the '
            'on-screen EQ/crossfader hides. Works with devices such as the EP-136 '
            '(set USB mode to Multi).',
            style: TextStyle(color: SideDeckTheme.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use external mixer'),
            subtitle: Text(
              widget.dj.externalMixer
                  ? 'ON — Deck A → channel 1, Deck B → channel 2 on the '
                      '${UsbOutput.deviceLabel(widget.dj.usbDeviceName)}'
                  : 'OFF — audio stays on the phone',
            ),
            value: widget.dj.externalMixer,
            onChanged: (v) async {
              await widget.dj.setExternalMixer(v);
              if (mounted) setState(() {});
            },
          ),
          const Divider(height: 32),
          const Text(
            'Subsonic server',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Optional. Tracks download to a local cache, then play like local files. '
            'Use http:// for a server on your LAN. Use https:// if the server is '
            'on the internet — otherwise the login token travels in the clear.',
            style: TextStyle(color: SideDeckTheme.muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://192.168.1.10:4533',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              labelText: 'Username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _saveAndTest,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save & ping'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(_status!),
          ],
          const Divider(height: 32),
          Center(
            child: Column(
              children: [
                const Text(
                  'TetalDJ',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                ),
                const Text(
                  'Versión $kAppVersion',
                  style: TextStyle(color: SideDeckTheme.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'TetalDJ',
                    applicationVersion: kAppVersion,
                    applicationLegalese:
                        'Basado en SideDeck (GNU GPL v3 o posterior) y software libre.',
                  ),
                  child: const Text(
                    'Licencias',
                    style: TextStyle(color: SideDeckTheme.muted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _midiSection(MidiController midi) {
    return AnimatedBuilder(
      animation: midi,
      builder: (context, _) {
        final ch = widget.dj.outputChannels;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Controladora MIDI',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(midi.status, style: const TextStyle(fontSize: 13)),
            if (midi.lastMessage.isNotEmpty)
              Text(
                'Último: ${midi.lastMessage}',
                style: const TextStyle(color: SideDeckTheme.muted, fontSize: 11),
              ),
            const SizedBox(height: 8),
            if (midi.devices.isEmpty)
              const Text(
                'No se ve ninguna controladora. Conéctala por USB (adaptador con '
                'carga) y toca Buscar.',
                style: TextStyle(color: SideDeckTheme.muted, fontSize: 12, height: 1.4),
              ),
            for (final MidiDevice d in midi.devices)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(d.name),
                subtitle: Text(d.type.toString().split('.').last),
                trailing: midi.connected?.id == d.id
                    ? TextButton(onPressed: midi.disconnect, child: const Text('Desconectar'))
                    : FilledButton(onPressed: () => midi.connect(d), child: const Text('Conectar')),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Modo vinilo en el jog'),
              subtitle: const Text('Tocar el plato hace scratch; apagado, solo pitch bend'),
              value: midi.vinylMode,
              onChanged: midi.setVinylMode,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Sonar por el celular'),
              subtitle: Text(widget.dj.outputRoute == 1
                  ? 'El audio sale por el parlante del teléfono aunque esté la controladora'
                  : widget.dj.outputIsUsb
                      ? 'Saliendo por la controladora (USB)'
                      : 'Automático: controladora si está conectada, si no el teléfono'),
              value: widget.dj.outputRoute == 1,
              onChanged: (v) {
                widget.dj.setOutputRoute(v ? 1 : 0);
                setState(() {});
              },
            ),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: midi.refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Buscar'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    widget.dj.restartAudio();
                    setState(() {});
                  },
                  icon: const Icon(Icons.headphones, size: 16),
                  label: Text('Audio: $ch canales · reconectar'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Con 4 canales (tarjeta de la controladora) el master sale por 1-2 y el '
              'cue de audífonos por 3-4. Si conectaste la controladora con la app '
              'abierta, toca reconectar.',
              style: TextStyle(color: SideDeckTheme.muted, fontSize: 12, height: 1.4),
            ),
          ],
        );
      },
    );
  }
}
