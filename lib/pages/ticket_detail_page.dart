import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'create_ticket_page.dart';

class TicketDetailPage extends StatelessWidget {
  final String ticketId;

  const TicketDetailPage({super.key, required this.ticketId});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('view_ticket'.tr()),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('tickets').doc(ticketId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text('error_loading'.tr()));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final subject = data['subject'] as String? ?? '';
          final messages = List<Map<String, dynamic>>.from(data['messages'] ?? []);
          final status = data['status'] as String? ?? 'pending';
          
          final bool isDismissed = status == 'dismissed';
          final bool isResolved = status == 'resolved';

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                color: Theme.of(context).colorScheme.secondary,
                child: Text(
                  subject,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 88),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final sender = msg['sender'] as String? ?? 'user';
                    final text = msg['text'] as String? ?? '';
                    final timestamp = msg['timestamp'] as Timestamp?;
                    final date = timestamp?.toDate();

                    final isUser = sender == 'user';
                    
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isUser 
                              ? Theme.of(context).primaryColor 
                              : Theme.of(context).colorScheme.secondary,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(16),
                            bottomLeft: isUser ? const Radius.circular(16) : const Radius.circular(0),
                          ),
                          border: isUser 
                              ? null 
                              : Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)),
                        ),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              text,
                              style: TextStyle(
                                fontSize: 15,
                                color: isUser 
                                    ? (isDarkMode ? Colors.black : Colors.white) 
                                    : Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              date != null ? '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}' : '',
                              style: TextStyle(
                                fontSize: 11,
                                color: isUser 
                                    ? (isDarkMode ? Colors.black54 : Colors.white70) 
                                    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (isDismissed || isResolved)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  color: isDismissed ? Theme.of(context).colorScheme.errorContainer : Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    isDismissed ? 'ticket_dismissed'.tr() : 'ticket_closed'.tr(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDismissed ? Theme.of(context).colorScheme.onErrorContainer : Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('tickets').doc(ticketId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox();
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final status = data['status'] as String? ?? 'pending';
          
          if (status == 'dismissed' || status == 'resolved') return const SizedBox();

          return FloatingActionButton.extended(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateTicketPage(replyToTicketId: ticketId),
                ),
              );
            },
            icon: const Icon(Icons.reply),
            label: Text('reply'.tr()),
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: isDarkMode ? Colors.black : Colors.white,
          );
        }
      ),
    );
  }
}
