# Nihongo Reader

Lector y anotador de libros para estudiar japonés en tablets Android, especialmente Xiaomi Pad 5.

## Incluye

- PDF editable: tinta con stylus, texto libre, resaltado, subrayado, búsqueda, formularios y guardado.
- EPUB: lectura paginada, selección, resaltado, subrayado, búsqueda y progreso CFI.
- DOCX: visor nativo con zoom, búsqueda y selección.
- DOC: se conserva en la biblioteca y se deriva al visor de documentos del sistema; DOCX es el formato Word recomendado para edición integrada.
- Biblioteca local: los libros importados se copian al almacenamiento privado de la app.
- Progreso y última página.
- OCR para PDFs escaneados.
- Diccionario interno como respaldo + botón para abrir Takoboto en Android.
- Esfera flotante de IA para explicar gramática, contexto, tono y vocabulario.
- API key del asistente guardada con almacenamiento seguro.
- Diseño Material 3 para tablet, con controles grandes y poco invasivos.

## Instalación

Como este repositorio parte vacío, genera una sola vez la estructura de plataforma:

flutter create .
flutter pub get
flutter run

Después abre el proyecto en VS Code o Android Studio con Flutter.

## EPUB

El lector EPUB utiliza flutter_epub_reader. En Android puede requerir los ajustes de WebView/cleartext indicados por ese paquete.

## IA

En Ajustes configura endpoint compatible con Chat Completions, modelo y API key. La clave se guarda con flutter_secure_storage y nunca debe subirse a GitHub.

## Takoboto

No se incluye ni se redistribuye la base de datos propietaria de Takoboto. La app intenta abrir Takoboto mediante su aplicación Android y, si no está disponible, utiliza su web como alternativa. El diccionario interno usa una consulta pública de respaldo.

## Arquitectura

La primera versión mantiene el código de aplicación compacto para que sea sencillo iterarlo. Luego se puede separar en features/library, features/reader, features/dictionary, features/assistant, data/models, data/services y platform/android.
