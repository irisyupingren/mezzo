import Mezzo

comp = defScore $ start $ melody :| c :| d :| e :| f :>> g

main :: IO ()
main = renderScore "comp.mid" "First composition" comp
