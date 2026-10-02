
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_pdf_editor/dart_pdf_editor.dart';
import 'package:docx_file_viewer/docx_file_viewer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_epub_reader/flutter_epub_reader.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const accent = Color(0xFF635BFF);
const paper = Color(0xFFF7F5F0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LibraryStore();
  await store.load();
  runApp(NihongoReaderApp(store: store));
}

class NihongoReaderApp extends StatelessWidget {
  const NihongoReaderApp({super.key, required this.store});
  final LibraryStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nihongo Reader',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: accent),
        scaffoldBackgroundColor: const Color(0xFFF4F1EB),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4F1EB),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            borderSide: BorderSide.none,
          ),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
        ),
      ),
      home: LibraryScreen(store: store),
    );
  }
}

enum BookType { pdf, epub, docx, doc }

class Book {
  Book({
    required this.id,
    required this.title,
    required this.path,
    required this.type,
    this.progress = 0,
    this.page = 0,
    this.lastOpened = 0,
  });

  final String id;
  String title;
  String path;
  BookType type;
  double progress;
  int page;
  int lastOpened;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'path': path,
        'type': type.name,
        'progress': progress,
        'page': page,
        'lastOpened': lastOpened,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        path: j['path'] as String,
        type: BookType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => BookType.pdf,
        ),
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 0,
        lastOpened: (j['lastOpened'] as num?)?.toInt() ?? 0,
      );
}

class LibraryStore extends ChangeNotifier {
  final books = <Book>[];
  SharedPreferences? prefs;
  Directory? dir;

  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    final root = await getApplicationDocumentsDirectory();
    dir = Directory(p.join(root.path, 'NihongoReader', 'Library'));
    await dir!.create(recursive: true);
    final raw = prefs!.getString('books');
    if (raw != null) {
      final data = jsonDecode(raw) as List<dynamic>;
      books
        ..clear()
        ..addAll(data.map((e) => Book.fromJson(e as Map<String, dynamic>)));
    }
    books.removeWhere((b) => !File(b.path).existsSync());
    await save();
  }

  Future<void> save() async {
    await prefs?.setString(
      'books',
      jsonEncode(books.map((b) => b.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<Book> importFile(PlatformFile picked) async {
    final source = picked.path;
    if (source == null) throw StateError('Android no entregó una ruta.');
    final ext = p.extension(source).toLowerCase();
    final type = switch (ext) {
      '.pdf' => BookType.pdf,
      '.epub' => BookType.epub,
      '.docx' => BookType.docx,
      '.doc' => BookType.doc,
      _ => throw UnsupportedError(ext),
    };
    final name = p.basenameWithoutExtension(source)
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final target = p.join(
      dir!.path,
      name + '-' + DateTime.now().millisecondsSinceEpoch.toString() + ext,
    );
    await File(source).copy(target);
    final book = Book(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: name,
      path: target,
      type: type,
      lastOpened: DateTime.now().millisecondsSinceEpoch,
    );
    books.insert(0, book);
    await save();
    return book;
  }

  Future<void> touch(Book b) async {
    b.lastOpened = DateTime.now().millisecondsSinceEpoch;
    await save();
  }

  Future<void> remove(Book b) async {
    final file = File(b.path);
    if (await file.exists()) await file.delete();
    books.removeWhere((x) => x.id == b.id);
    await save();
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, required this.store});
  final LibraryStore store;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String query = '';

  Future<void> addBook() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'epub', 'docx', 'doc'],
    );
    if (picked == null) return;
    try {
      await widget.store.importFile(picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo importar: ' + e.toString())));
    }
  }

  void open(Book b) {
    widget.store.touch(b);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderScreen(store: widget.store, book: b)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final items = widget.store.books
            .where((b) => b.title.toLowerCase().contains(query.toLowerCase()))
            .toList();
        final recent = [...widget.store.books]
          ..sort((a, b) => b.lastOpened.compareTo(a.lastOpened));

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'Nihongo Reader',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: [
              IconButton(
                tooltip: 'Ajustes',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                icon: const Icon(Icons.tune_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: addBook,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Añadir libro'),
          ),
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        colors: [Color(0xFF242038), Color(0xFF4A3F7A)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tu biblioteca de estudio',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Lee, escribe, consulta y aprende dentro del libro.',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          onPressed: addBook,
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (recent.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  sliver: SliverToBoxAdapter(
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => open(recent.first),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Row(
                            children: [
                              BookIcon(type: recent.first.type, large: true),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Continuar leyendo',
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      recent.first.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    LinearProgressIndicator(
                                      value: recent.first.progress,
                                      minHeight: 6,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                sliver: SliverToBoxAdapter(
                  child: TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: const InputDecoration(
                      hintText: 'Buscar en tu biblioteca…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                sliver: items.isEmpty
                    ? SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(50),
                            child: Column(
                              children: [
                                const Icon(Icons.library_books_outlined,
                                    size: 70, color: Colors.black26),
                                const SizedBox(height: 14),
                                const Text(
                                  'Tu biblioteca está vacía',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Importa PDF, EPUB, DOCX o DOC desde el selector de archivos.',
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                  onPressed: addBook,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Importar'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 310,
                          mainAxisExtent: 270,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final b = items[index];
                            return Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => open(b),
                                child: Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          BookIcon(type: b.type),
                                          const Spacer(),
                                          PopupMenuButton<String>(
                                            onSelected: (v) async {
                                              if (v == 'delete') {
                                                await widget.store.remove(b);
                                              }
                                            },
                                            itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text('Eliminar'),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const Spacer(),
                                      Text(
                                        b.title,
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      LinearProgressIndicator(
                                        value: b.progress,
                                        minHeight: 6,
                                        borderRadius: BorderRadius.circular(99),
                                      ),
                                      const SizedBox(height: 6),
                                      Text((b.progress * 100).round().toString() + '%'),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          childCount: items.length,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class BookIcon extends StatelessWidget {
  const BookIcon({super.key, required this.type, this.large = false});
  final BookType type;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final icon = switch (type) {
      BookType.pdf => Icons.picture_as_pdf_rounded,
      BookType.epub => Icons.auto_stories_rounded,
      BookType.docx => Icons.description_rounded,
      BookType.doc => Icons.article_rounded,
    };
    return Container(
      width: large ? 64 : 54,
      height: large ? 74 : 62,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            color: Color(0x16000000),
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Icon(icon, color: accent, size: large ? 32 : 27),
    );
  }
}

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.store, required this.book});
  final LibraryStore store;
  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  String selected = '';

  void dictionary() => showDictionary(context, selected);
  void assistant() => showAssistant(
        context,
        selected,
        widget.book.title,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.book.type == BookType.pdf
          ? null
          : AppBar(
              title: Text(
                widget.book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              actions: [
                IconButton(
                  tooltip: 'Diccionario',
                  onPressed: dictionary,
                  icon: const Icon(Icons.translate_rounded),
                ),
                IconButton(
                  tooltip: 'Context Sensei',
                  onPressed: assistant,
                  icon: const Icon(Icons.auto_awesome_rounded),
                ),
              ],
            ),
      body: Stack(
        children: [
          switch (widget.book.type) {
            BookType.pdf => PdfReaderPane(
                store: widget.store,
                book: widget.book,
                onSelection: (s) => setState(() => selected = s),
              ),
            BookType.epub => EpubReaderPane(
                store: widget.store,
                book: widget.book,
                onSelection: (s) => setState(() => selected = s),
              ),
            BookType.docx => DocxReaderPane(
                book: widget.book,
              ),
            BookType.doc => LegacyDocPane(book: widget.book),
          },
          if (widget.book.type != BookType.pdf)
            Positioned(
              right: 18,
              bottom: 22,
              child: FloatingActionButton.small(
                heroTag: 'sensei',
                onPressed: assistant,
                child: const Icon(Icons.auto_awesome_rounded),
              ),
            ),
        ],
      ),
    );
  }
}

class PdfReaderPane extends StatefulWidget {
  const PdfReaderPane({super.key, required this.store, required this.book, required this.onSelection});
  final LibraryStore store;
  final Book book;
  final ValueChanged<String> onSelection;
  @override State<PdfReaderPane> createState() => _PdfReaderPaneState();
}

class _PdfReaderPaneState extends State<PdfReaderPane> {
  late final PdfEditingController editing;
  late final PdfViewerController viewer;
  Timer? _chromeTimer;
  bool _chromeVisible = false;

  @override
  void initState() {
    super.initState();
    final bytes = File(widget.book.path).readAsBytesSync();
    editing = PdfEditingController(Uint8List.fromList(bytes));
    viewer = PdfViewerController();
    // Stylus-first mode: fingers/palm never create ink; only the pen draws.
    editing.preferences.fingerDrawsInk = false;
    editing.preferences.color = const Color(0xFF263238);
    editing.preferences.strokeWidth = 1.6;
    editing.preferences.opacity = 0.88;
    editing.inkCommitDelay = const Duration(milliseconds: 420);
    editing.preferences.showThumbnailSidebar = false;
    editing.preferences.showBookmarkSidebar = false;
    editing.preferences.showAnnotationSidebar = false;
    viewer.addListener(changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.book.page > 0) viewer.jumpToPage(widget.book.page);
    });
  }

  void changed() {
    widget.onSelection(viewer.selectedText);
    if (viewer.pageCount > 0) {
      widget.book.page = viewer.currentPage;
      widget.book.progress = ((viewer.currentPage + 1) / viewer.pageCount).clamp(0, 1);
      unawaited(widget.store.save());
    }
  }

  Future<void> savePdf() async {
    await File(widget.book.path).writeAsBytes(editing.bytes, flush: true);
    await widget.store.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cambios guardados.')));
  }

  void showChrome() {
    _chromeTimer?.cancel();
    if (mounted && !_chromeVisible) setState(() => _chromeVisible = true);
    _chromeTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  @override
  void dispose() {
    _chromeTimer?.cancel();
    unawaited(savePdf());
    editing.dispose();
    viewer.dispose();
    super.dispose();
  }

  void setTool(PdfEditTool? tool) {
    editing.tool = editing.tool == tool ? null : tool;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.deferToChild,
            onPointerDown: (_) => showChrome(),
            child: PdfViewer(
            controller: viewer, editing: editing, documentId: widget.book.id,
            backgroundColor: const Color(0xFFE7E4DE),
            initialFit: PdfViewerFit.page, contextMenuEnabled: true,
            textSelectionEditing: true, textSelectionMarkup: true,
            ),
          ),
        ),
        Positioned(
          top: 14,
          left: 14,
          right: 14,
          child: AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    _ReaderPill(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ReaderToolButton(icon: Icons.pan_tool_outlined, label: 'Leer', active: editing.tool == null, onTap: () => setTool(null)),
                          _ReaderToolButton(icon: Icons.edit_rounded, label: 'Lápiz', active: editing.tool == PdfEditTool.ink, onTap: () => setTool(PdfEditTool.ink)),
                          _ReaderToolButton(icon: Icons.highlight_rounded, label: 'Marcar', active: editing.tool == PdfEditTool.highlight, onTap: () => setTool(PdfEditTool.highlight)),
                          _ReaderToolButton(icon: Icons.auto_fix_high_rounded, label: 'Borrar', active: editing.tool == PdfEditTool.eraser, onTap: () => setTool(PdfEditTool.eraser)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    _ReaderPill(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(tooltip: 'Diccionario', onPressed: () => showDictionary(context, viewer.selectedText), icon: const Icon(Icons.translate_rounded, size: 20)),
                          IconButton(tooltip: 'Context Sensei', onPressed: () => showAssistant(context, viewer.selectedText, widget.book.title), icon: const Icon(Icons.auto_awesome_rounded, size: 20)),
                          IconButton(tooltip: 'Guardar', onPressed: savePdf, icon: const Icon(Icons.cloud_done_outlined, size: 20)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: SafeArea(
            top: false,
            child: Center(
              child: AnimatedOpacity(
                opacity: _chromeVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: _ReaderPill(
                  child: AnimatedBuilder(
                    animation: viewer,
                    builder: (context, _) {
                      return Text(
                        'Página ' +
                            (viewer.currentPage + 1).toString() +
                            ' / ' +
                            viewer.pageCount.toString(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .2,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReaderPill extends StatelessWidget {
  const _ReaderPill({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: .94), elevation: 8,
    shadowColor: Colors.black.withValues(alpha: .12),
    borderRadius: BorderRadius.circular(18),
    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: child),
  );
}

class _ReaderToolButton extends StatelessWidget {
  const _ReaderToolButton({required this.icon, required this.label, required this.active, required this.onTap});
  final IconData icon; final String label; final bool active; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: IconButton(
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: active ? accent.withValues(alpha: .12) : Colors.transparent,
        foregroundColor: active ? accent : Colors.black54,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
      icon: Icon(icon, size: 21),
    ),
  );
}
class EpubReaderPane extends StatefulWidget {
  const EpubReaderPane({
    super.key,
    required this.store,
    required this.book,
    required this.onSelection,
  });
  final LibraryStore store;
  final Book book;
  final ValueChanged<String> onSelection;

  @override
  State<EpubReaderPane> createState() => _EpubReaderPaneState();
}

class _EpubReaderPaneState extends State<EpubReaderPane> {
  final controller = EpubController();
  String? cfi;

  @override
  Widget build(BuildContext context) {
    return EpubViewer(
      epubSource: EpubSource.fromFile(File(widget.book.path)),
      epubController: controller,
      initialCfi: cfi,
      displaySettings: const EpubDisplaySettings(
        flow: EpubFlow.paginated,
        snap: true,
      ),
      onRelocated: (location) {
        cfi = location.startCfi;
        widget.book.progress = location.progress;
        unawaited(widget.store.save());
      },
      onTextSelected: (selection) {
        widget.onSelection(selection.selectedText);
      },
    );
  }
}

class DocxReaderPane extends StatelessWidget {
  const DocxReaderPane({super.key, required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    return DocxView(
      file: File(book.path),
      config: DocxViewConfig(
        enableSearch: true,
        enableZoom: true,
        enableSelection: true,
        pageMode: DocxPageMode.paged,
        backgroundColor: const Color(0xFFDEDAD3),
        theme: DocxViewTheme.light(),
      ),
    );
  }
}

class LegacyDocPane extends StatelessWidget {
  const LegacyDocPane({super.key, required this.book});
  final Book book;

  Future<void> openExternal() async {
    final ok = await launchUrl(
      Uri.file(book.path),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) throw StateError('No hay un visor DOC instalado.');
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.description_outlined, size: 80),
            const SizedBox(height: 18),
            const Text(
              'Documento Word antiguo (.doc)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              'El archivo queda guardado en la biblioteca. Para este formato antiguo se recomienda abrirlo con el visor de documentos instalado o convertirlo a DOCX para una experiencia integrada.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: openExternal,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Abrir externamente'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAssistant(
  BuildContext context,
  String selected,
  String bookTitle,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => AssistantSheet(
      selectedText: selected,
      bookTitle: bookTitle,
    ),
  );
}

class AssistantSheet extends StatefulWidget {
  const AssistantSheet({
    super.key,
    required this.selectedText,
    required this.bookTitle,
  });
  final String selectedText;
  final String bookTitle;

  @override
  State<AssistantSheet> createState() => _AssistantSheetState();
}

class _AssistantSheetState extends State<AssistantSheet> {
  final input = TextEditingController();
  final messages = <Map<String, String>>[];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    input.text = widget.selectedText;
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> ask() async {
    final q = input.text.trim();
    if (q.isEmpty || loading) return;
    setState(() {
      loading = true;
      messages.add({'role': 'user', 'text': q});
    });
    input.clear();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final answer = LocalSensei().answer(
      book: widget.bookTitle,
      selected: widget.selectedText,
      question: q,
      history: messages,
    );
    if (mounted) {
      setState(() {
        messages.add({'role': 'assistant', 'text': answer});
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        height: 620,
        decoration: const BoxDecoration(
          color: paper,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 45,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: accent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Context Sensei', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                        Text('Sensei local · funciona sin Internet', style: TextStyle(fontSize: 12, color: Colors.black45)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            if (widget.selectedText.trim().isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 18),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(widget.selectedText, maxLines: 4, overflow: TextOverflow.ellipsis),
              ),
            Expanded(
              child: messages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: Text(
                          'Puedo ayudarte con traducción, partículas, conjugaciones, vocabulario, gramática y contexto. No necesitas Internet.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(18),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final m = messages[i];
                        final user = m['role'] == 'user';
                        return Align(
                          alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 600),
                            margin: const EdgeInsets.only(bottom: 9),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: user ? accent : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Text(
                              m['text'] ?? '',
                              style: TextStyle(color: user ? Colors.white : Colors.black87, height: 1.45),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => ask(),
                      decoration: const InputDecoration(
                        hintText: 'Pregunta a Sensei…',
                        prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: loading ? null : ask,
                    icon: loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.arrow_upward_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LocalSensei {
  static const particles = <String, String>{
    'は': 'marca el tema de la oración.',
    'が': 'marca el sujeto o información focal.',
    'を': 'marca normalmente el objeto directo.',
    'に': 'puede marcar destino, momento, existencia o destinatario.',
    'で': 'puede marcar el lugar de una acción o un medio.',
    'と': 'puede indicar compañía («con») o aparecer en una cita.',
    'も': 'suele expresar «también» o «tampoco».',
    'の': 'conecta elementos, a menudo con relación posesiva o atributiva.',
    'から': 'puede expresar origen o razón, según el contexto.',
    'まで': 'indica normalmente un límite («hasta»).',
  };

  static const vocabulary = <String, String>{
    '昨日': 'きのう — ayer',
    '今日': 'きょう — hoy',
    '明日': 'あした / あす — mañana',
    '友達': 'ともだち — amigo/a',
    '映画': 'えいが — película',
    '学校': 'がっこう — escuela',
    '先生': 'せんせい — profesor/a',
    '学生': 'がくせい — estudiante',
    '日本': 'にほん / にっぽん — Japón',
    '日本語': 'にほんご — idioma japonés',
    '本': 'ほん — libro',
    '時間': 'じかん — tiempo / horas',
    '食べる': 'たべる — comer',
    '飲む': 'のむ — beber',
    '見る': 'みる — ver / mirar',
    '行く': 'いく — ir',
    '来る': 'くる — venir',
    'する': 'する — hacer',
    '読む': 'よむ — leer',
    '書く': 'かく — escribir',
  };

  String answer({
    required String book,
    required String selected,
    required String question,
    required List<Map<String, String>> history,
  }) {
    final q = question.toLowerCase();
    final text = selected.trim();

    if (q.contains('qué significa') || q.contains('que significa') ||
        q.contains('traduce') || q.contains('traduc') || q.contains('significado')) {
      return _translation(text);
    }
    if (q.contains('partícula') || q.contains('particula') ||
        q.contains('por qué') || q.contains('por que')) {
      return _particleExplanation(text);
    }
    if (q.contains('gramática') || q.contains('gramatica') ||
        q.contains('estructura') || q.contains('conjug')) {
      return _grammar(text);
    }
    if (q.contains('palabra') || q.contains('vocabulario') || q.contains('vocab')) {
      return _vocabulary(text);
    }
    if (q.contains('nivel') || q.contains('jlpt')) {
      return _level(text);
    }
    if (q.contains('hola') || q.contains('buenas') || q == 'こんにちは') {
      return 'こんにちは！ Soy Context Sensei. Estoy integrado en Nihongo Reader y funciono sin conexión. Pregúntame por una palabra, partícula, gramática, traducción o nivel JLPT.';
    }
    if (text.isNotEmpty) {
      return 'Estoy analizando «' + text + '».\\n\\n'
          'Puedo ayudarte con:\\n'
          '• «¿Qué significa?»\\n'
          '• «¿Por qué usa esta partícula?»\\n'
          '• «¿Qué gramática aparece?»\\n'
          '• «¿Qué palabras importantes hay?»\\n'
          '• «¿Qué nivel JLPT tiene?»\\n\\n'
          'Haz una pregunta de seguimiento y mantendré el contexto de esta conversación.';
    }
    return 'Selecciona una frase japonesa en el libro y pregúntame sobre ella.';
  }

  String _translation(String text) {
    if (text.isEmpty) return 'No hay una frase seleccionada.';
    final known = vocabulary.entries.where((e) => text.contains(e.key))
        .map((e) => '• ' + e.key + ': ' + e.value).toList();
    final particleList = particles.keys.where(text.contains).toList();
    return 'Análisis de «' + text + '»\\n\\n' +
        (known.isEmpty ? 'No tengo todavía una entrada local para las palabras de esta frase.'
            : 'Vocabulario reconocido:\\n' + known.join('\\n')) +
        '\\n\\n' +
        (particleList.isEmpty ? 'No detecté una partícula frecuente de mi base local.'
            : 'Partículas detectadas: ' + particleList.join('、')) +
        '\\n\\nPara una traducción completa de cualquier frase, ampliaremos progresivamente la base lingüística local de Sensei.';
  }

  String _particleExplanation(String text) {
    final found = particles.keys.where(text.contains).toList();
    if (found.isEmpty) return 'No detecté は、が、を、に、で、へ、と、も、の、から o まで en el fragmento seleccionado.';
    final lines = found.map((p) => '• ' + p + ' — ' + particles[p]!).join('\\n');
    return 'En «' + text + '» detecto estas partículas:\\n\\n' + lines +
        '\\n\\nEl significado exacto depende de la construcción y del contexto.';
  }

  String _grammar(String text) {
    if (text.isEmpty) return 'Selecciona una frase para analizar su gramática.';
    final clues = <String>[];
    if (text.contains('ました')) clues.add('• 〜ました: forma pasada cortés de los verbos.');
    if (text.contains('ません')) clues.add('• 〜ません: forma negativa cortés.');
    if (text.contains('たい')) clues.add('• 〜たい: expresa deseo de hacer algo.');
    if (text.contains('ている')) clues.add('• 〜ている: puede expresar una acción en curso o un estado resultante.');
    if (text.contains('ない')) clues.add('• 〜ない: forma negativa informal de muchos verbos/adjetivos.');
    if (clues.isEmpty) return 'No detecté todavía una estructura que pueda identificar con seguridad en «' + text + '».';
    return 'Estructuras reconocidas en «' + text + '»:\\n\\n' + clues.join('\\n');
  }

  String _vocabulary(String text) {
    final found = vocabulary.entries.where((e) => text.contains(e.key))
        .map((e) => '• ' + e.key + ': ' + e.value).toList();
    if (found.isEmpty) return 'No encontré palabras de mi vocabulario local en «' + text + '». La base se ampliará con contenido JLPT.';
    return 'Vocabulario reconocido:\\n\\n' + found.join('\\n');
  }

  String _level(String text) {
    final score = vocabulary.keys.where(text.contains).length +
        particles.keys.where(text.contains).length;
    if (score >= 5) return 'Hay varios elementos básicos reconocibles. El nivel JLPT exacto no puede determinarse de forma fiable solo con esta heurística.';
    if (score >= 2) return 'La frase contiene elementos frecuentes de nivel inicial. No sería fiable asignarle un nivel JLPT exacto todavía.';
    return 'No tengo suficiente información local para asignar un nivel JLPT fiable a esta frase.';
  }
}

class DictionaryEntry {
  const DictionaryEntry({
    required this.word,
    required this.reading,
    required this.meanings,
  });
  final String word;
  final String reading;
  final List<String> meanings;
}

class DictionaryService {
  Future<List<DictionaryEntry>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final uri = Uri.parse(
      'https://jisho.org/api/v1/search/words?keyword=' +
          Uri.encodeComponent(q),
    );
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw StateError('Diccionario HTTP ' + response.statusCode.toString());
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = data['data'] as List<dynamic>? ?? const [];
    return rows.take(8).map((raw) {
      final row = raw as Map<String, dynamic>;
      final jp = (row['japanese'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final senses = (row['senses'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>();
      final word =
          jp.isNotEmpty ? (jp.first['word'] ?? '').toString() : '';
      final reading =
          jp.isNotEmpty ? (jp.first['reading'] ?? '').toString() : '';
      final meanings = senses
          .take(3)
          .expand(
            (s) => (s['english_definitions'] as List<dynamic>? ?? const [])
                .map((x) => x.toString()),
          )
          .toList();
      return DictionaryEntry(
        word: word,
        reading: reading,
        meanings: meanings,
      );
    }).toList();
  }

  Future<void> openTakoboto(String query) async {
    final q = Uri.encodeComponent(query);
    final intent = Uri.parse(
      'intent:#Intent;package=jp.takoboto;action=jp.takoboto.SEARCH;S.q=' +
          q +
          ';end',
    );
    if (await canLaunchUrl(intent)) {
      await launchUrl(intent);
      return;
    }
    await launchUrl(
      Uri.parse('https://takoboto.jp/?q=' + q),
      mode: LaunchMode.externalApplication,
    );
  }
}

Future<void> showDictionary(BuildContext context, String initial) {
  final text = TextEditingController(text: initial);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: paper,
    builder: (_) => DictionarySheet(controller: text),
  ).whenComplete(text.dispose);
}

class DictionarySheet extends StatefulWidget {
  const DictionarySheet({super.key, required this.controller});
  final TextEditingController controller;

  @override
  State<DictionarySheet> createState() => _DictionarySheetState();
}

class _DictionarySheetState extends State<DictionarySheet> {
  final service = DictionaryService();
  List<DictionaryEntry> results = [];
  bool loading = false;

  Future<void> search() async {
    setState(() => loading = true);
    try {
      final r = await service.search(widget.controller.text);
      if (mounted) setState(() => results = r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height * .78;
    return SizedBox(
      height: h.clamp(450, 700),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 45,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 12, 10),
            child: Row(
              children: [
                const Icon(Icons.translate_rounded, color: accent),
                const SizedBox(width: 10),
                const Text(
                  'Diccionario japonés',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    autofocus: widget.controller.text.isEmpty,
                    onSubmitted: (_) => search(),
                    decoration: const InputDecoration(
                      hintText: '日本語 / kana / romaji / English',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: loading ? null : search,
                  icon: const Icon(Icons.search_rounded),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 18, top: 6),
              child: TextButton.icon(
                onPressed: () => service.openTakoboto(widget.controller.text),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Abrir en Takoboto'),
              ),
            ),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: results.isEmpty
                ? const Center(
                    child: Text(
                      'Selecciona una palabra del libro o escríbela aquí.',
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(18),
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final e = results[i];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.word.isEmpty ? e.reading : e.word,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (e.reading.isNotEmpty)
                                Text(
                                  e.reading,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              const SizedBox(height: 8),
                              Text(e.meanings.join(' · ')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Context Sensei', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Sensei funciona de forma local dentro de Nihongo Reader. No necesita API key, cuenta de OpenAI ni conexión a Internet.'),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(color: accent.withValues(alpha: .10), borderRadius: BorderRadius.circular(14)),
                    child: const Icon(Icons.offline_bolt_rounded, color: accent),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Modo local activo', style: TextStyle(fontWeight: FontWeight.w800)),
                        SizedBox(height: 4),
                        Text('Análisis y conversación disponibles sin Internet.'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Qué puede hacer ahora', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          const Text(
  '• Analizar texto seleccionado\\n• Explicar partículas frecuentes\\n• Reconocer vocabulario local\\n• Detectar algunas conjugaciones y estructuras\\n• Responder preguntas de seguimiento\\n• Mantener el contexto durante la conversación',
  style: TextStyle(height: 1.55),
),
          const SizedBox(height: 24),
          const Text('Próxima expansión', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('La arquitectura está preparada para ampliar Sensei con una base local de vocabulario, gramática y contenido JLPT, aumentando sus respuestas sin depender de servicios externos.'),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 18),
          const Text('Biblioteca', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Los libros importados se copian al almacenamiento privado de la aplicación. El selector de Android entrega acceso solo al archivo que eliges.'),
          const SizedBox(height: 24),
          const Text('Xiaomi Pad 5 + stylus', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('El editor PDF utilizado por la app ofrece tinta con presión, suavizado, rechazo de palma y borrado de tinta cuando el dispositivo expone esos eventos al sistema.'),
        ],
      ),
    );
  }
}
