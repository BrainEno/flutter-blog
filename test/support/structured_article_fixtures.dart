/// Contract-shaped no-wave v1 article. Text containing Markdown syntax is
/// intentionally literal: only the explicit runs carry formatting.
Map<String, dynamic> structuredArticle() => {
  'id': 'article-uuid',
  'slug': 'structured',
  'title': 'Sample title',
  'authorId': 'author',
  'summary': 'A summary',
  'updatedAt': '2026-10-01T00:00:00Z',
  'contentBlocksVersion': 1,
  'contentBlocks': [
    {
      'id': 'heading',
      'type': 'heading',
      'level': 2,
      'text': 'Bold代码',
      'inlines': [
        {
          'text': 'Bold',
          'marks': ['bold', 'italic', 'underline', 'strikethrough'],
          'href': '/guide',
        },
        {
          'text': '代码',
          'marks': ['code', 'bold', 'italic', 'underline', 'strikethrough'],
          'href': 'https://external.example/path',
        },
      ],
    },
    {
      'id': 'image-one',
      'type': 'image',
      'src': '/media/one.png',
      'alt': 'First image alt',
      'caption': 'First caption',
    },
    {'id': 'paragraph', 'type': 'paragraph', 'text': 'literal **asterisks**'},
    {
      'id': 'quote',
      'type': 'quote',
      'text': 'Quoted words',
      'attribution': 'Author name',
      'inlines': [
        {
          'text': 'Quoted ',
          'marks': ['italic'],
        },
        {
          'text': 'words',
          'marks': ['bold'],
        },
      ],
    },
    {
      'id': 'list',
      'type': 'list',
      'ordered': true,
      'items': ['First item', ' second item '],
      'itemInlines': [
        [
          {
            'text': 'First ',
            'marks': ['bold'],
          },
          {'text': 'item'},
        ],
        [
          {
            'text': ' second item ',
            'marks': ['underline'],
          },
        ],
      ],
    },
    {
      'id': 'image-two',
      'type': 'image',
      'src': '/media/two.png',
      'alt': 'Second image alt',
      'caption': 'Second caption',
    },
    {'id': 'code', 'type': 'code', 'language': 'dart', 'code': '  a\n\n b  \n'},
  ],
};
