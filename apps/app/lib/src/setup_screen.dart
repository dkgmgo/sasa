import 'package:flutter/material.dart';

import 'setup_controller.dart';

/// First-run setup (also reachable from Settings): synced folder, calendar
/// source, CalDAV account.
class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.controller,
    required this.onDone,
    this.firstRun = true,
  });

  final SetupController controller;

  /// Called after everything was saved.
  final VoidCallback onDone;
  final bool firstRun;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  SetupController get _c => widget.controller;
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  bool _loaded = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _c.load().then((_) {
      if (!mounted) return;
      _url.text = _c.url;
      _user.text = _c.username;
      setState(() => _loaded = true);
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (await _c.finish()) {
      _password.clear();
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.firstRun ? 'Set up Sasa' : 'Folder and account'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListenableBuilder(
              listenable: _c,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.firstRun)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Sasa reads your calendars and keeps its own data in '
                        'a folder you already sync between your devices '
                        '(Syncthing, Nextcloud).',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  _folderSection(context),
                  if (_c.isAndroid) _sourceSection(context),
                  _accountSection(context),
                  if (_c.error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _c.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _c.busy || _c.blocker != null ? null : _finish,
                    child: Text(widget.firstRun ? 'Finish' : 'Save'),
                  ),
                  if (_c.blocker != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _c.blocker!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _folderSection(BuildContext context) {
    final folder = _c.folder;
    final devices = _c.existingDevices;
    return _Section(
      number: 1,
      title: 'Synced folder',
      children: [
        Text(
          'Choose the folder your sync app shares between devices. Sasa '
          'writes only inside a "Sasa" folder in it. Passwords are never '
          'stored there.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            folder == null ? Icons.folder_off_outlined : Icons.folder_outlined,
          ),
          title: Text(folder?.name ?? 'No folder chosen'),
          subtitle: folder == null
              ? null
              : Text(switch (devices) {
                  null || 0 => 'No Sasa data yet: it will be created.',
                  1 => 'Sasa data from 1 device found.',
                  _ => 'Sasa data from $devices devices found.',
                }),
          trailing: OutlinedButton(
            onPressed: _c.busy ? null : _c.pickFolder,
            child: Text(folder == null ? 'Choose' : 'Change'),
          ),
        ),
      ],
    );
  }

  Widget _sourceSection(BuildContext context) {
    return _Section(
      number: 2,
      title: 'Calendars and tasks',
      children: [
        RadioGroup<bool>(
          groupValue: _c.useDavx,
          onChanged: (v) => _c.setUseDavx(v ?? true),
          child: const Column(
            children: [
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: true,
                title: Text('DAVx⁵ on this phone'),
                subtitle: Text(
                  'Read what DAVx⁵ already synced (calendar and Tasks.org). '
                  'Asks for calendar access.',
                ),
              ),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: false,
                title: Text('CalDAV server'),
                subtitle: Text('Read the server directly.'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _accountSection(BuildContext context) {
    final optional = !_c.calDavRequired;
    return _Section(
      number: _c.isAndroid ? 3 : 2,
      title: optional ? 'CalDAV account (optional)' : 'CalDAV account',
      children: [
        Text(
          optional
              ? 'Used for tasks when Tasks.org is not installed. Read only: '
                    'Sasa never changes your calendars.'
              : 'Read only: Sasa never changes your calendars.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://dav.example.org/',
            errorText: _url.text.isEmpty ? null : _c.urlError,
            helperText: _c.urlInsecure
                ? 'Not encrypted: your password would be readable on '
                      'the network. Use https:// if you can.'
                : null,
            helperMaxLines: 2,
          ),
          onChanged: _c.setUrl,
        ),
        TextField(
          controller: _user,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'User name',
            errorText: _user.text.isEmpty ? null : _c.usernameError,
          ),
          onChanged: _c.setUsername,
        ),
        TextField(
          controller: _password,
          obscureText: !_showPassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: _c.hasSavedPassword
                ? 'Saved. Leave empty to keep it.'
                : 'Kept in this device\'s secure storage.',
            suffixIcon: IconButton(
              tooltip: _showPassword ? 'Hide password' : 'Show password',
              icon: Icon(
                _showPassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
          ),
          onChanged: _c.setPassword,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: _c.canTestConnection ? _c.testConnection : null,
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Test connection'),
            ),
            const SizedBox(width: 8),
            if (_c.connectionMessage != null)
              Expanded(
                child: Text(
                  _c.connectionMessage!,
                  style: TextStyle(
                    color: _c.connectionOk == true
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    required this.children,
  });

  final int number;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$number · $title',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
}
