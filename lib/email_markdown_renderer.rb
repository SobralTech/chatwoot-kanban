class EmailMarkdownRenderer < BaseMarkdownRenderer
  def blockquote(node)
    block do
      container(
        "<blockquote#{sourcepos(node)} style=\"margin:0 0 0 .8ex;border-left:1px solid #ccc;padding-left:1ex;\">\n",
        '</blockquote>'
      ) { out(:children) }
    end
  end
end
