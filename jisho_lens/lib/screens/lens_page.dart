import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:jisho_lens/components/search_results.dart';
import 'package:jisho_lens/components/search_warning.dart';
import 'package:jisho_lens/constants/kana_patterns.dart';
import 'package:jisho_lens/extensions/context_extensions.dart';
import 'package:jisho_lens/extensions/sizedbox_extensions.dart';
import 'package:jisho_lens/models/scanned_image.dart';
import 'package:jisho_lens/providers/jmdict_provider.dart';
import 'package:jisho_lens/providers/search_settings_provider.dart';
import 'package:jisho_lens/services/scanned_image_painter.dart';
import 'package:jisho_lens/providers/ocr_provider.dart';
import 'package:jisho_lens/services/text_elements_painter.dart';
import 'package:jisho_lens/services/word_extractor.dart';
import 'package:sliding_up_panel/sliding_up_panel.dart';

class LensPage extends ConsumerStatefulWidget {
  const LensPage({super.key});

  @override
  LensPageState createState() => LensPageState();
}

class LensPageState extends ConsumerState<LensPage> {
  final _wordExtractor = WordExtractor();
  final _panelController = PanelController();
  final _interactiveViewController = TransformationController();
  final _kanjiPattern = RegExp("[$kKanjiPattern]");

  // this is a bit of a hack to remember that we've set the initial position
  // of the InteractiveViewer. If we don't do this, the viewer will get transformed
  // everytime it gets rebuilt.
  bool transformed = false;

  @override
  void initState() {
    super.initState();
    // scale to minimum size on initial view
    _interactiveViewController.value = Matrix4.identity();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _wordExtractor.initMecab();
    });
  }

  @override
  void dispose() {
    _interactiveViewController.dispose();
    _wordExtractor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = ref.watch(selectedImagePath);
    final searchResult = ref.watch(jMDictNotifierProvider);
    final line = ref.watch(selectedLine);
    final word = ref.watch(selectedWord);

    BorderRadiusGeometry radius = const BorderRadius.only(
      topLeft: Radius.circular(16.0),
      topRight: Radius.circular(16.0),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black, Colors.transparent],
            ),
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      body: Visibility(
        visible: imagePath != null,
        replacement: const Text("Image path was null"),
        child: SlidingUpPanel(
          controller: _panelController,
          minHeight: 80,
          backdropEnabled: true,
          parallaxEnabled: true,
          borderRadius: radius,
          body: FutureBuilder(
            future: _loadScannedImage(imagePath ?? ""),
            builder: (
              BuildContext context,
              AsyncSnapshot<ScannedImageData> snapshot,
            ) {
              if (!snapshot.hasData && snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final image = snapshot.data!.image;
              final textLines = snapshot.data!.textLines!;

              if (textLines.isEmpty) {
                return Center(
                  child: Text(
                    "No Japanese text was recognised.\n"
                    "Try scanning a different image.",
                    style: context.theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                );
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (transformed) return;
                // scale image to fit the screen on initial load
                _scaleToFit(image);
                setState(() {
                  transformed = true;
                });
              });

              return Visibility(
                // only show the image when it's been transformed so we won't get weird glitches
                visible: transformed,
                replacement: const Center(child: CircularProgressIndicator()),
                child: InteractiveViewer(
                  transformationController: _interactiveViewController,
                  constrained: false,
                  boundaryMargin: EdgeInsets.symmetric(
                    horizontal: 0,
                    vertical: MediaQuery.of(context).size.height,
                  ),
                  minScale: 0.1,
                  maxScale: 1.0,
                  child: Builder(builder: (gestureContext) {
                    return GestureDetector(
                      onTapDown: (details) => _selectText(gestureContext, details, textLines),
                      child: FittedBox(
                        child: SizedBox(
                          width: image.width.toDouble(),
                          height: image.height.toDouble(),
                          child: CustomPaint(
                            painter: ScannedImagePainter(
                              image: image,
                            ),
                            foregroundPainter: TextElementsPainter(
                              textLines: textLines,
                              selectedLineIndex: ref.watch(selectedLineIndex),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
          panel: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              color: context.theme.colorScheme.background,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: 32,
                          child: ListView.separated(
                            physics: const BouncingScrollPhysics(),
                            scrollDirection: Axis.horizontal,
                            separatorBuilder: (context, index) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final text = line[index];
                              var background = context.theme.colorScheme.primary.withOpacity(
                                text == word ? 0.2 : 0.05,
                              );
                              return GestureDetector(
                                onTap: () {
                                  final useFuzzySearch = ref.read(searchSettingsNotifierProvider).useFuzzySearch;

                                  if (!_kanjiPattern.hasMatch(text) && text.length <= 1 && useFuzzySearch) {
                                    showDialog(
                                      context: context,
                                      builder: (_) => const SearchWarningDialog(),
                                    );
                                    return;
                                  }

                                  ref.read(selectedWord.notifier).state = text;
                                  ref.read(jMDictNotifierProvider.notifier).updateResults(
                                        keyword: text,
                                        fuzzy: useFuzzySearch,
                                      );
                                  _panelController.open();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: background,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(text),
                                ),
                              );
                            },
                            itemCount: line.length,
                          ),
                        ),
                        16.verticalBox,
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Visibility(
                            visible: searchResult != null && searchResult.vocabularies.isNotEmpty,
                            replacement: Container(),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Fetched ${searchResult?.rowsCount} rows in ${searchResult?.duration}ms.",
                                  style: context.theme.textTheme.bodySmall,
                                ),
                                Text(
                                  "${searchResult?.resultCount} results found.",
                                  style: context.theme.textTheme.bodySmall,
                                )
                              ],
                            ),
                          ),
                        ),
                        if (line.isNotEmpty)
                          SearchResults(
                            searchResult: searchResult,
                            searchKeyword: selectedWord,
                          )
                        else
                          Container()
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<ScannedImageData> _loadScannedImage(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final image = await decodeImageFromList(bytes);
    final textLines = await _wordExtractor.extractAsLines(imagePath);

    return ScannedImageData(
      image: image,
      textLines: textLines,
    );
  }

  void _selectText(
    BuildContext context,
    TapDownDetails details,
    List<TextLine> textLines,
  ) {
    RenderBox box = context.findRenderObject() as RenderBox;
    final local = box.globalToLocal(details.globalPosition);
    final lineIndex = textLines.indexWhere((element) => element.boundingBox.contains(local));

    // resets everything when the user clicked outside of any text
    if (lineIndex == -1) {
      ref.read(selectedLineIndex.notifier).state = -1;
      ref.read(selectedLine.notifier).state = [];
      return;
    }

    // reset the search result when the user clicked  on a different line
    ref.read(jMDictNotifierProvider.notifier).reset();
    ref.read(selectedWord.notifier).state = "";

    final words = _wordExtractor.splitToWords(textLines[lineIndex].text);

    ref.read(selectedLineIndex.notifier).state = lineIndex;
    ref.read(selectedLine.notifier).state = words;
  }

  void _scaleToFit(ui.Image image) {
    // use the parent widget's context
    RenderBox box = context.findRenderObject() as RenderBox;
    final width = box.size.width;
    final height = box.size.height - 80;
    // scale the image to fit the screen width
    final scale = width / image.width;
    // translate on Y axis to center the image if the image is smaller than the screen height
    final translate = image.height < height ? (height - image.height * scale) / 2 : 0.0;

    _interactiveViewController.value = Matrix4.identity()
      ..scale(scale)
      // it's the m[2][3] element of the matrix
      // but since flutter uses column-major order, we need to use m[1][3]
      ..setEntry(1, 3, translate);
  }
}
