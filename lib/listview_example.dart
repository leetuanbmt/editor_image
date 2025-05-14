import 'package:flutter/material.dart';

class ListViewExample extends StatefulWidget {
  const ListViewExample({Key? key}) : super(key: key);

  @override
  State<ListViewExample> createState() => _ListViewExampleState();
}

class _ListViewExampleState extends State<ListViewExample> {
  final List<String> items = List.generate(100, (index) => 'Mục ${index + 1}');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ví dụ ListView trong Flutter')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Các loại ListView',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Cơ bản'),
                      Tab(text: 'Builder'),
                      Tab(text: 'Separated'),
                    ],
                    labelColor: Colors.blue,
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildStandardListView(),
                        _buildBuilderListView(),
                        _buildSeparatedListView(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardListView() {
    return ListView(
      padding: const EdgeInsets.all(8.0),
      children:
          items
              .take(20)
              .map(
                (item) => ListTile(
                  title: Text(item),
                  leading: const Icon(Icons.article),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _showItemDetails(item),
                ),
              )
              .toList(),
    );
  }

  Widget _buildBuilderListView() {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: items.length,
      itemBuilder: (context, index) {
        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: ListTile(
            title: Text(items[index]),
            subtitle: Text('Mô tả ngắn cho ${items[index]}'),
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Text('${index + 1}'),
            ),
            onTap: () => _showItemDetails(items[index]),
          ),
        );
      },
    );
  }

  Widget _buildSeparatedListView() {
    return ListView.separated(
      padding: const EdgeInsets.all(8.0),
      itemCount: items.length,
      separatorBuilder:
          (context, index) => const Divider(color: Colors.grey, height: 1),
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      items[index],
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Đây là mô tả chi tiết cho ${items[index].toLowerCase()}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () => _showItemDetails(items[index]),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showItemDetails(String item) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bạn đã chọn: $item'),
        duration: const Duration(seconds: 1),
      ),
    );
  }
}
