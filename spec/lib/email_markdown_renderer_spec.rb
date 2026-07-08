require 'rails_helper'

describe EmailMarkdownRenderer do
  let(:renderer) { described_class.new }

  def render_markdown(markdown)
    doc = CommonMarker.render_doc(markdown, :DEFAULT)
    renderer.render(doc)
  end

  it 'is a subclass of BaseMarkdownRenderer' do
    expect(described_class.superclass).to eq(BaseMarkdownRenderer)
  end

  describe '#blockquote' do
    it 'renders the blockquote with the Gmail-style inline border/indent' do
      result = render_markdown('> quoted text')
      expect(result).to include('<blockquote')
      expect(result).to include('margin:0 0 0 .8ex')
      expect(result).to include('border-left:1px solid #ccc')
      expect(result).to include('padding-left:1ex')
      expect(result).to include('quoted text')
    end

    it 'does not force a text color on the quoted content' do
      result = render_markdown('> quoted text')
      expect(result).not_to include('color:')
    end

    it 'still nests blockquotes correctly for a reply chain' do
      result = render_markdown("> level one\n> > level two")
      expect(result.scan('<blockquote').count).to eq(2)
      expect(result).to include('level one')
      expect(result).to include('level two')
    end
  end

  describe '#image' do
    it 'behaves identically to BaseMarkdownRenderer for images' do
      markdown = '![Sample Title](https://example.com/image.jpg?cw_image_height=100)'
      expect(render_markdown(markdown)).to include('<img src="https://example.com/image.jpg?cw_image_height=100" style="height: 100;" />')
    end
  end

  describe 'other tags' do
    it 'renders paragraphs the same as BaseMarkdownRenderer' do
      result = render_markdown('**bold** _italic_')
      expect(result).to include('<strong>bold</strong>')
      expect(result).to include('<em>italic</em>')
    end
  end
end
