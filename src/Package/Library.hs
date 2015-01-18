{-# LANGUAGE NoImplicitPrelude #-}
module Package.Library (buildPackageLibrary) where

import Package.Base

argListDir :: FilePath
argListDir = "shake/arg/buildPackageLibrary"

arArgs :: [FilePath] -> FilePath -> Args
arArgs objs result = args [ arg "q"
                          , arg result
                          , args objs ]

arRule :: Package -> TodoItem -> Rules ()
arRule pkg @ (Package _ path _) todo @ (stage, dist, _) =
    let buildDir = path </> dist </> "build"
    in
    (buildDir <//> "*a") %> \out -> do
        let way = detectWay $ tail $ takeExtension out
        depHsObjs <- pkgDepHsObjects path dist way
        cObjs <- pkgCObjects path dist way
        need $ [argListPath argListDir pkg stage] ++ depHsObjs ++ cObjs
        libHsObjs <- pkgLibHsObjects path dist stage way
        liftIO $ removeFiles "." [out]
        -- Splitting argument list into chunks as otherwise Ar chokes up
        maxChunk <- argSizeLimit
        forM_ (chunksOfSize maxChunk $ libHsObjs ++ cObjs) $ \os -> do
            run Ar $ arArgs os $ toStandard out

ldArgs :: Package -> TodoItem -> FilePath -> Args
ldArgs (Package _ path _) (stage, dist, _) result = do
    hObjs <- pkgDepHsObjects path dist vanilla
    cObjs <- pkgCObjects path dist vanilla
    need $ hObjs ++ cObjs
    args [ args $ ConfLdLinkerArgs stage
         , arg "-r"
         , arg "-o"
         , arg result
         , args $ hObjs ++ cObjs ]

ldRule :: Package -> TodoItem -> Rules ()
ldRule pkg @ (Package name path _) todo @ (stage, dist, _) =
    let pathDist = path </> dist
        buildDir = pathDist </> "build"
    in
    priority 2 $ (buildDir </> "*.o") %> \out -> do
        need [argListPath argListDir pkg stage]
        run Ld $ ldArgs pkg todo $ toStandard out
        synopsis <- dropWhileEnd isPunctuation <$> showArg (Synopsis pathDist)
        putColoured Green $ "/--------\n| Successfully built package "
            ++ name ++ " (stage " ++ show stage ++ ")."
        putColoured Green $ "| Package synopsis: " ++ synopsis ++ "."
            ++ "\n\\--------"

argListRule :: Package -> TodoItem -> Rules ()
argListRule pkg @ (Package _ path _) todo @ (stage, dist, settings) =
    (argListPath argListDir pkg stage) %> \out -> do
        need $ ["shake/src/Package/Library.hs"] ++ sourceDependecies
        ways' <- ways settings
        ldList <- argList Ld (ldArgs pkg todo "output.o")
        arList <- forM ways' $ \way -> do
            cObjs <- pkgCObjects path dist way
            libHsObjs <- pkgLibHsObjects path dist stage way
            extension <- libsuf way
            argListWithComment
                ("way '" ++ tag way ++ "'")
                Ar
                (arArgs (libHsObjs ++ cObjs) $ "output" <.> extension)
        writeFileChanged out $ unlines $ [ldList] ++ arList

buildPackageLibrary :: Package -> TodoItem -> Rules ()
buildPackageLibrary = argListRule <> arRule <> ldRule