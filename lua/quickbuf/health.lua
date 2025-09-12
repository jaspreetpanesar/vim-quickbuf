return {
  check = function()
    vim.health.start("vim-quickbuf report")

    if vim.fn.executable("fzf") then
      vim.health.ok("fzf is installed")
    else
      vim.health.warn("fzf not installed")
    end

    if vim.fn.has("nvim-0.12") then
      vim.health.ok("fuzzy match can be used")
    else
      vim.health.warn(
        "fuzzy match not available on current nvim version"
      )
    end

  end
}
