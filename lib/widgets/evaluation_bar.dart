import 'package:flutter/material.dart';

class EvaluationBar extends StatelessWidget {
  final double? evaluation; // in pawns
  final int depth;
  
  const EvaluationBar({
    Key? key,
    required this.evaluation,
    required this.depth,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (evaluation == null) {
      return SizedBox(
        width: 40,
        child: Column(
          children: [
            // Depth indicator
            Container(
              height: 20,
              color: Colors.grey[300],
              child: Center(
                child: Text(
                  'depth: ?',
                  style: TextStyle(fontSize: 8, color: Colors.grey[600]),
                ),
              ),
            ),
            // Bar
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  border: Border.all(color: Colors.grey[400]!, width: 1),
                ),
                child: const Center(
                  child: Text('?', style: TextStyle(fontSize: 10)),
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    // Clamp evaluation between -10 and +10 pawns
    final clampedEval = evaluation!.clamp(-10.0, 10.0);
    // Convert to percentage (0 = black winning, 1 = white winning)
    final whiteAdvantage = (clampedEval + 10) / 20;
    
    // Ensure we always have at least 1% for each side
    final whiteFlex = (whiteAdvantage * 100).round().clamp(1, 99);
    final blackFlex = 100 - whiteFlex;
    
    return SizedBox(
      width: 40,
      child: Column(
        children: [
          // Depth indicator at top
          Container(
            height: 20,
            color: Colors.blue[700],
            child: Center(
              child: Text(
                'depth: $depth',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          // Evaluation bar
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[600]!, width: 2),
              ),
              child: Column(
                children: [
                  // White advantage section (top)
                  Expanded(
                    flex: whiteFlex,
                    child: Container(
                      color: Colors.white,
                      child: Center(
                        child: evaluation! > 0.3
                            ? Text(
                                '+${evaluation!.toStringAsFixed(1)}',
                                style: TextStyle(
                                  color: Colors.grey[800],
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  // Center line
                  Container(
                    height: 2,
                    color: Colors.grey[600],
                  ),
                  // Black advantage section (bottom)
                  Expanded(
                    flex: blackFlex,
                    child: Container(
                      color: Colors.grey[900],
                      child: Center(
                        child: evaluation! < -0.3
                            ? Text(
                                evaluation!.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              )
                            : null,
                      ),
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
}