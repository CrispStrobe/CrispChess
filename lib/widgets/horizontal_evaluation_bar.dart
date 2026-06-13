import 'package:flutter/material.dart';

class HorizontalEvaluationBar extends StatelessWidget {
  final double? evaluation; // in pawns
  final int depth;
  
  const HorizontalEvaluationBar({
    Key? key,
    required this.evaluation,
    required this.depth,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    if (evaluation == null) {
      return Container(
        height: 30,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
          child: Text(
            'Analyzing...',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ),
      );
    }
    
    // Clamp evaluation between -10 and +10 pawns
    final clampedEval = evaluation!.clamp(-10.0, 10.0);
    // Convert to percentage (0 = black winning, 1 = white winning)
    final whiteAdvantage = (clampedEval + 10) / 20;
    
    return Container(
      height: 30,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[400]!, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(
          children: [
            // Background (black side)
            Container(color: Colors.grey[800]),
            
            // White advantage overlay (from left)
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: whiteAdvantage,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white,
                      Colors.grey[100]!,
                    ],
                  ),
                ),
              ),
            ),
            
            // Center line marker
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 2,
                color: Colors.grey[600],
              ),
            ),
            
            // Evaluation text
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      evaluation! >= 0 
                          ? '+${evaluation!.toStringAsFixed(1)}'
                          : evaluation!.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'd$depth',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}