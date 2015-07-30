module Main

import Control.Algebra
import Graphics.Util.Math3D as T
import Data.Matrix

import Graphics.Rendering.Gl
import Graphics.Util.Glfw
import Graphics.Rendering.Config
import Graphics.Util.ObjLoader

%include C "GL/glew.h"


Position: Type
Position = Vect 3 Double

Color: Type
Color = Vect 3 Double

showError : String -> IO ()
showError msg = do err <- glGetError
                   putStrLn $ msg ++ (show err)
                   
record Shaders where
  constructor MkShaders
  program: Program
  shaderIds: List Shader
  transformationMatrix: Int
  lightPosition : Int
  lightColor: Int
  specularReflectivity : Int
  shininess : Int

createShaders : IO Shaders
createShaders = do
  glGetError
  vertexShader <- glCreateShader GL_VERTEX_SHADER
  
  vtx <- readFile "shader.vert"
  glShaderSource vertexShader vtx
  glCompileShader vertexShader
  printShaderLog vertexShader

  fragmentShader <- glCreateShader GL_FRAGMENT_SHADER

  frg <- readFile "shader.frag"
  glShaderSource fragmentShader frg 
  glCompileShader fragmentShader  
  printShaderLog fragmentShader

  program <- glCreateProgram
  glAttachShader program vertexShader
  glAttachShader program fragmentShader
  
  glLinkProgram program
  glUseProgram program
  showError "link and use "
  printShaderLog vertexShader
  printShaderLog fragmentShader

  locView <- glGetUniformLocation program "viewMatrix"
  glUniformMatrix4fv locView defaultViewMatrix

  locProj <- glGetUniformLocation program "projectionMatrix"
  let projM = perspectiveProjection (Degree 45) (800 / 600) (1.0, 100.0)
  glUniformMatrix4fv locProj $ projM

  loc <- glGetUniformLocation program "transformMatrix"

  locLightPos <- glGetUniformLocation program "lightPosition"
  locLightColor <- glGetUniformLocation program "lightColor"

  --locSpecIntensity    <- glGetUniformLocation program "lightIntensitySpecular"
  locSpecReflectivity <- glGetUniformLocation program "reflectivitySpecular"
  glUniform3fv locSpecReflectivity [0.2,0.2,0.2] 
  
  locShininess        <- glGetUniformLocation program "shininessFactor"
  glUniform1f locShininess 10.0
  
  pure $ MkShaders program [fragmentShader, vertexShader] loc locLightPos locLightColor locSpecReflectivity locShininess
  

destroyShaders : Shaders -> IO ()
destroyShaders shaders = do
  glGetError
  glUseProgram noProgram
  glDetachShaders (program shaders) (shaderIds shaders)
  glDeleteShaders (shaderIds shaders)
  glDeleteProgram (program shaders)
  showError "delete shaders "
  pure ()
  
record Light where
  constructor MkLight
  position: Position
  color: Color

record Model where
  constructor MkModel
  vao : Vao
  positions : Buffer 
  uvs : Buffer 
  normals : Buffer
  indices : Buffer
  numIndices : Int

record TexturedModel where
  constructor MkTexturedModel
  model : Model
  texture: Texture

toList' : List (Vect m a) -> List a
toList' xs = flatten $ map toList xs

createBuffers : String -> IO Model
createBuffers filename = do 
  putStrLn $ "loading " ++ (show filename)
  
  (MkObjModel pos uvs norm ind) <- loadObj filename
  putStrLn $ "positions " ++ (show $ length pos)
  putStrLn $ "uvs " ++ (show $ length uvs)
  putStrLn $ "normals " ++ (show $ length norm)
  putStrLn $ "indices " ++ (show $ length ind)
  
  glGetError

  vao <- glGenVertexArrays
  glBindVertexArray vao

  positionBuffer <- glGenBuffers
  glBindBuffer GL_ARRAY_BUFFER positionBuffer
  glBufferData GL_ARRAY_BUFFER (toList' pos) GL_STATIC_DRAW
  glEnableVertexAttribArray 0
  glVertexAttribPointer 0 3 GL_DOUBLE GL_FALSE 0 0

  uvBuffer <- glGenBuffers
  glBindBuffer GL_ARRAY_BUFFER uvBuffer
  glBufferData GL_ARRAY_BUFFER (toList' uvs) GL_STATIC_DRAW
  glEnableVertexAttribArray 1
  glVertexAttribPointer 1 2 GL_DOUBLE GL_FALSE 0 0

  normalBuffer <- glGenBuffers
  glBindBuffer GL_ARRAY_BUFFER normalBuffer
  glBufferData GL_ARRAY_BUFFER (toList' norm) GL_STATIC_DRAW
  glEnableVertexAttribArray 2
  glVertexAttribPointer 2 3 GL_DOUBLE GL_FALSE 0 0

  indexBuffer <- glGenBuffers
  glBindBuffer GL_ELEMENT_ARRAY_BUFFER indexBuffer
  glBufferDatai GL_ELEMENT_ARRAY_BUFFER ind GL_STATIC_DRAW

  showError "buffers "
  pure $ MkModel vao positionBuffer uvBuffer normalBuffer indexBuffer (toIntNat $ length ind)


destroyBuffers : Model -> IO ()
destroyBuffers model = do
  showError "destroy buffers "
  glDisableVertexAttribArray 2
  glDisableVertexAttribArray 1
  glDisableVertexAttribArray 0
  
  glUnbindBuffer GL_ARRAY_BUFFER
  glUnbindBuffer GL_ELEMENT_ARRAY_BUFFER

  showError "destroy buffers "
  glDeleteBuffer $ positions model
  glDeleteBuffer $ uvs model
  glDeleteBuffer $ normals model
  glDeleteBuffer $ indices model

  glUnbindVertexArray
  
  glDeleteVertexArray $ vao model

  showError "destroy buffers "

draw : GlfwWindow -> List TexturedModel -> Vect 3 Double -> Shaders -> Light -> IO ()
draw win models rotation shaders light = do 
                   glClearColor 0.2 0.2 0.2 1
                   glClear GL_COLOR_BUFFER_BIT
                   glClear GL_DEPTH_BUFFER_BIT
                   
                   let loc = transformationMatrix shaders
                   glUniformMatrix4fv loc $ (translate [0, -1.3, -5]) <> (rotate $ map Degree rotation) <> (scaleAll 1)

                   let locLightPos = lightPosition shaders
                   glUniform3fv locLightPos (position light)
                   let locLightCol = lightColor shaders
                   glUniform3fv locLightCol (color light)

                   let (model1 :: model2 :: model3 :: []) = models
                   glBindTexture GL_TEXTURE_2D (texture model1)
                   glBindVertexArray $ vao (model model1)
                   glDrawElements GL_TRIANGLES $ numIndices (model model1)

                   glBindTexture GL_TEXTURE_2D (texture model2)
                   glBindVertexArray $ vao (model model2)
                   glDrawElements GL_TRIANGLES $ numIndices (model model2)

                   glBindTexture GL_TEXTURE_2D (texture model3)
                   glBindVertexArray $ vao (model model3)
                   glDrawElements GL_TRIANGLES $ numIndices (model model3)
                                      
                   glfwSwapBuffers win
                   
initDisplay : String -> Int -> Int -> IO GlfwWindow
initDisplay title width height = do
  glfw <- glfwInit
  glfwWindowHint GLFW_CONTEXT_VERSION_MAJOR  4
  glfwWindowHint GLFW_CONTEXT_VERSION_MINOR  1
  glfwWindowHint GLFW_OPENGL_FORWARD_COMPAT  1
  glfwWindowHint GLFW_OPENGL_PROFILE         (toInt GLFW_OPENGL_CORE_PROFILE)
  win <- glfwCreateWindow title width height defaultMonitor
  glfwMakeContextCurrent win
  glewInit
  info <- glGetInfo
  putStrLn info
  glEnable GL_DEPTH_TEST
  glDepthFunc GL_LESS
  glEnable GL_CULL_FACE
  return win

main : IO ()
main = do win <- initDisplay "Hello Idris" 800 600
          glfwSetInputMode win GLFW_STICKY_KEYS 1
          glfwSwapInterval 0
          shaders <- createShaders
          --model <- createBuffers "cube.obj"
          --model <- createBuffers "whisky_bottles.obj"
          model1 <- createBuffers "ball_diffuse.obj"
          glActiveTexture GL_TEXTURE0 -- load the texture into unit 0
          texture1 <- glLoadPNGTexture "logo2.png"

          -- the texture is bound ... so we can set some params
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_S GL_CLAMP_TO_EDGE
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_T GL_CLAMP_TO_EDGE
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_LINEAR
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_LINEAR

          model2 <- createBuffers "ball_spec.obj"
          glActiveTexture GL_TEXTURE0 -- load the texture into unit 0
          texture2 <- glLoadPNGTexture "red.png"
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_S GL_REPEAT
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_T GL_REPEAT
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_LINEAR
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_LINEAR

          model3 <- createBuffers "plane.obj"
          glActiveTexture GL_TEXTURE0 -- load the texture into unit 0
          texture3 <- glLoadPNGTexture "tiles.png"
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_S GL_REPEAT
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_WRAP_T GL_REPEAT
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MIN_FILTER GL_LINEAR
          glTexParameteri GL_TEXTURE_2D GL_TEXTURE_MAG_FILTER GL_LINEAR

                              
          let light = MkLight [0,0,1] [1,1,1] 
          
          eventLoop win [(MkTexturedModel model1 texture1), (MkTexturedModel model2 texture2), (MkTexturedModel model3 texture3)] [0,0,0] shaders light
          glDeleteTextures [texture1, texture2]
          destroyBuffers model1
          destroyBuffers model2
          destroyBuffers model3
          destroyShaders shaders
          glfwDestroyWindow win
          glfwTerminate
          pure ()
       where 
         eventLoop : GlfwWindow -> List TexturedModel -> Vect 3 Double -> Shaders -> Light -> IO ()
         eventLoop win models rotation shaders light = do
                      draw win models rotation shaders light
                      --let newRotation = Graphics.Util.Math3D.(+) rotation [0.0, 0.025, 0]
                      glfwPollEvents
                      key <- glfwGetFunctionKey win GLFW_KEY_ESCAPE
                      shouldClose <- glfwWindowShouldClose win
                      if shouldClose || key == GLFW_PRESS
                      then pure ()
                      else eventLoop win models rotation shaders light
                              
 
