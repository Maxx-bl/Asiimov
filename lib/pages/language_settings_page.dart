import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentLocale = context.locale.languageCode;
    
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('language'.tr()),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            physics: const BouncingScrollPhysics(),
            children: [
              const SizedBox(height: 10),
              
              _LanguageTile(
                title: 'fran_ais'.tr(),
                languageCode: 'fr',
                isSelected: currentLocale == 'fr',
                onTap: () {
                  context.setLocale(const Locale('fr'));
                },
              ),
              
              _LanguageTile(
                title: 'english'.tr(),
                languageCode: 'en',
                isSelected: currentLocale == 'en',
                onTap: () {
                  context.setLocale(const Locale('en'));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  final String title;
  final String languageCode;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.title,
    required this.languageCode,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected 
              ? Theme.of(context).primaryColor 
              : Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
          width: isSelected ? 2 : 1,
        ),
      ),
      margin: const EdgeInsets.only(left: 25, top: 12, right: 25),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        trailing: isSelected 
            ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
            : null,
        onTap: onTap,
      ),
    );
  }
}
