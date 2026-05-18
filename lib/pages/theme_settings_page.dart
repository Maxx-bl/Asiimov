import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:asiimov/themes/theme_provider.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  final TextEditingController _hexController = TextEditingController();
  Color _previewColor = Colors.orange;
  String? _errorMessage;

  final List<String> _curatedColors = [
    'FF9800', // Orange
    '2196F3', // Neon Blue
    '00E5FF', // Aqua Cyan
    '00E676', // Spring Green
    '9C27B0', // Purple
    'E91E63', // Hot Pink
    'FFEB3B', // Cyberpunk Yellow
    'FF5252', // Coral Red
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ThemeProvider>(context, listen: false);
      final currentHex = ThemeProvider.colorToHex(provider.dominantColor);
      _hexController.text = currentHex;
      setState(() {
        _previewColor = provider.dominantColor;
      });
    });
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _onHexChanged(String value) {
    if (value.length == 6) {
      try {
        final parsedColor = ThemeProvider.hexToColor(value);
        setState(() {
          _previewColor = parsedColor;
          _errorMessage = null;
        });
      } catch (e) {
        setState(() {
          _errorMessage = 'Invalid Hex code';
        });
      }
    } else {
      setState(() {
        _errorMessage = 'Hex code must be 6 characters';
      });
    }
  }

  void _applyColor(Color color, String hexCode) {
    Provider.of<ThemeProvider>(context, listen: false).setDominantColor(color);
    setState(() {
      _errorMessage = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Dominant color updated to #$hexCode successfully!'),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final activeColor = themeProvider.dominantColor;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Theme'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Section 1: Dark Mode Toggle
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                    ),
                  ),
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.moon_stars,
                            color: activeColor,
                            size: 26,
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'Dark Mode',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      CupertinoSwitch(
                        value: themeProvider.isDarkMode,
                        activeTrackColor: activeColor,
                        onChanged: (value) =>
                            themeProvider.toggleTheme(),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Section 2: Dominant Color Header
                Text(
                  'DOMINANT COLOR',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a vibrant accent color that will be applied across the entire app interface instead of the classic orange.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Section 2 Panel
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                    ),
                  ),
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vibrant Palette',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      // Curated horizontal list
                      SizedBox(
                        height: 48,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _curatedColors.length,
                          itemBuilder: (context, index) {
                            final hex = _curatedColors[index];
                            final color = ThemeProvider.hexToColor(hex);
                            final isSelected = ThemeProvider.colorToHex(activeColor) == hex;
                            
                            return GestureDetector(
                              onTap: () {
                                _hexController.text = hex;
                                setState(() {
                                  _previewColor = color;
                                });
                                _applyColor(color, hex);
                              },
                              child: Container(
                                margin: const EdgeInsets.only(right: 12),
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Colors.white : Colors.transparent,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: color.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: isSelected
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 16,
                                      )
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Divider(height: 1),
                      ),
                      
                      Text(
                        'Custom Hex Code',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      
                      Row(
                        children: [
                          // Prefix #
                          Text(
                            '#',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          
                          // Input box
                          Expanded(
                            child: TextField(
                              controller: _hexController,
                              onChanged: _onHexChanged,
                              maxLength: 6,
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(6),
                                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
                              ],
                              decoration: InputDecoration(
                                hintText: 'FFFFFF',
                                counterText: '',
                                errorText: _errorMessage,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide(
                                    color: activeColor,
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          
                          // Color preview box
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: _previewColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white24,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _previewColor.withValues(alpha: 0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Apply Button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _hexController.text.length == 6 && _errorMessage == null
                              ? () => _applyColor(_previewColor, _hexController.text)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: activeColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: activeColor.withValues(alpha: 0.3),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Apply Custom Color',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
