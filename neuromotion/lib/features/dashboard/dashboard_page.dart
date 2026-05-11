import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final mockPatients = [
      ('P-24031', 'Liam W.', 'Post-op Week 3'),
      ('P-24032', 'Olivia H.', 'ACL Rehab Week 6'),
      ('P-24033', 'Noah K.', 'Neuro Gait Follow-up'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('NeuroMotion Dashboard'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'North Shore Private Hospital',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'AI gait analytics for objective clinical assessment.',
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => context.push('/capture'),
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    label: const Text('Start New Assessment'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_done_rounded, color: Colors.green),
              title: const Text('System Status'),
              subtitle: const Text('RTX 5070 Server Connection: Online'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Online',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Patient Records',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          ...mockPatients.map(
            (patient) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text('${patient.$2} (${patient.$1})'),
                subtitle: Text(patient.$3),
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
