import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  final int strengthLevel;
  final int hintDepth;
  
  const SettingsScreen({
    Key? key, 
    required this.strengthLevel,
    required this.hintDepth,
  }) : super(key: key);
  
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _strengthLevel;
  late int _hintDepth;
  bool _showValidMoves = true;
  bool _animateMoves = true;
  
  @override
  void initState() {
    super.initState();
    _strengthLevel = widget.strengthLevel;
    _hintDepth = widget.hintDepth;
  }
  
  String _getStrengthDescription(int level) {
    if (level <= 3) return 'Beginner (Learning)';
    if (level <= 6) return 'Novice (Casual)';
    if (level <= 10) return 'Intermediate';
    if (level <= 14) return 'Advanced';
    if (level <= 17) return 'Expert';
    return 'Master+';
  }
  
  int _getEstimatedElo(int level) {
    return 800 + (level * 80);
  }
  
  int _getSearchDepth(int level) {
    return 3 + level;
  }
  
  Color _getColorForStrength(int level) {
    if (level <= 6) return Colors.green;
    if (level <= 10) return Colors.blue;
    if (level <= 14) return Colors.orange;
    if (level <= 17) return Colors.red;
    return Colors.purple;
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Text(
            'Opponent Strength',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: 8),
          Text(
            'Uses multiple techniques: Skill Level + ELO limiting + Search depth',
            style: TextStyle(color: Colors.grey[600], fontSize: 12, fontStyle: FontStyle.italic),
          ),
          SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Level $_strengthLevel',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _getStrengthDescription(_strengthLevel),
                            style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                      Chip(
                        label: Text(
                          _getStrengthDescription(_strengthLevel),
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        backgroundColor: _getColorForStrength(_strengthLevel),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Slider(
                    value: _strengthLevel.toDouble(),
                    min: 0,
                    max: 20,
                    divisions: 20,
                    label: _strengthLevel.toString(),
                    onChanged: (value) {
                      setState(() => _strengthLevel = value.round());
                    },
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Technical Details:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.speed, size: 16, color: Colors.blue.shade700),
                            SizedBox(width: 8),
                            Text(
                              'Skill Level: $_strengthLevel/20',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.trending_up, size: 16, color: Colors.blue.shade700),
                            SizedBox(width: 8),
                            Text(
                              'Estimated ELO: ~${_getEstimatedElo(_strengthLevel)}',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.layers, size: 16, color: Colors.blue.shade700),
                            SizedBox(width: 8),
                            Text(
                              'Search Depth: ${_getSearchDepth(_strengthLevel)} moves',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          SizedBox(height: 24),
          
          Text(
            'Hint System',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: 8),
          Text(
            'Hints always use maximum engine strength',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          SizedBox(height: 16),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Analysis Depth: $_hintDepth',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Chip(
                        label: Text(
                          _hintDepth < 12 ? 'Quick' : _hintDepth < 18 ? 'Strong' : 'Maximum',
                          style: TextStyle(color: Colors.white),
                        ),
                        backgroundColor: _hintDepth < 12 ? Colors.blue : _hintDepth < 18 ? Colors.purple : Colors.deepPurple,
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Slider(
                    value: _hintDepth.toDouble(),
                    min: 8,
                    max: 22,
                    divisions: 14,
                    label: _hintDepth.toString(),
                    onChanged: (value) {
                      setState(() => _hintDepth = value.round());
                    },
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Higher depth = Better hints but slower (${_hintDepth < 12 ? "~1s" : _hintDepth < 18 ? "~3s" : "~5s"})',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          
          SizedBox(height: 24),
          
          Text(
            'Visual Settings',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text('Show Valid Moves'),
                  subtitle: Text('Highlight legal moves when selecting a piece'),
                  value: _showValidMoves,
                  onChanged: (value) {
                    setState(() => _showValidMoves = value);
                  },
                ),
                Divider(height: 1),
                SwitchListTile(
                  title: Text('Animate Moves'),
                  subtitle: Text('Smooth piece movement animation'),
                  value: _animateMoves,
                  onChanged: (value) {
                    setState(() => _animateMoves = value);
                  },
                ),
              ],
            ),
          ),
          
          SizedBox(height: 24),
          
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 20, color: Colors.green.shade700),
                      SizedBox(width: 8),
                      Text(
                        'How Strength Limiting Works',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'CrispChess uses a multi-layered approach:\n\n'
                    '1. Skill Level (0-20): Makes engine play less accurately\n'
                    '2. ELO Rating: Targets specific playing strength\n'
                    '3. Search Depth: Limits how far ahead engine thinks\n\n'
                    'Combined, these create realistic human-like play at any level.',
                    style: TextStyle(fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pop(context, {
            'strengthLevel': _strengthLevel,
            'hintDepth': _hintDepth,
            'showValidMoves': _showValidMoves,
            'animateMoves': _animateMoves,
          });
        },
        icon: Icon(Icons.check),
        label: Text('Save'),
      ),
    );
  }
}