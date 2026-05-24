import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'create_ticket_page.dart';
import 'ticket_detail_page.dart';

class SupportTicketsPage extends StatelessWidget {
  const SupportTicketsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    if (currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text('support_tickets'.tr())),
        body: Center(child: Text('user_not_logged_in'.tr())),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text('support_tickets'.tr()),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tickets')
            .where('userId', isEqualTo: currentUser.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('error_loading'.tr()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          final allTickets = snapshot.data!.docs;
          final tickets = allTickets.toList();
          
          tickets.sort((a, b) {
            final aTime = (a.data() as Map<String, dynamic>)['updatedAt'] as Timestamp?;
            final bTime = (b.data() as Map<String, dynamic>)['updatedAt'] as Timestamp?;
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return bTime.compareTo(aTime);
          });

          if (tickets.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 48, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)),
                  const SizedBox(height: 16),
                  Text('no_tickets_found'.tr(), style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80, top: 12),
            itemCount: tickets.length,
            itemBuilder: (context, index) {
              final ticketDoc = tickets[index];
              final data = ticketDoc.data() as Map<String, dynamic>;
              final subject = data['subject'] as String? ?? '';
              final status = data['status'] as String? ?? 'pending';
              final timestamp = data['updatedAt'] as Timestamp?;
              final date = timestamp?.toDate();

              final bool isAnswered = status == 'answered';
              final bool isResolved = status == 'resolved';
              final bool isDismissed = status == 'dismissed';
              
              final Color statusColor;
              if (isDismissed) {
                statusColor = Colors.red;
              } else if (isResolved) {
                statusColor = Colors.blue;
              } else if (isAnswered) {
                statusColor = Colors.green;
              } else {
                statusColor = Theme.of(context).colorScheme.primary.withValues(alpha: 0.6);
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                elevation: 0,
                color: Theme.of(context).colorScheme.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    subject,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isDismissed ? 'ticket_dismissed'.tr() :
                            isResolved ? 'ticket_closed'.tr() :
                            isAnswered ? 'ticket_answered'.tr() : 
                            'ticket_pending'.tr(),
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (date != null)
                          Text(
                            '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => TicketDetailPage(ticketId: ticketDoc.id),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CreateTicketPage(),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: Text('new_ticket'.tr()),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: isDarkMode ? Colors.black : Colors.white,
      ),
    );
  }
}
