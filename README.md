# TODO:
- insert extmarks to maintain them sorted based on the start
- extmark_to_loc function
- binary search current cursor 
```lua
[buf] = {
    {
        m_start = mark_id,
        ns = name,
        m_end = mark_id, 
    }, -- a range
}
```
