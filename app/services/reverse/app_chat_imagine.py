"""
AppChat-based image generation service.

Uses the app-chat API instead of WebSocket to generate images,
which can help avoid WebSocket 429 rate limiting issues.
"""

import re
import asyncio
from typing import Any, AsyncGenerator, Dict, List, Optional

from app.core.config import get_config
from app.core.logger import logger
from app.services.reverse.app_chat import AppChatReverse
from app.services.reverse.utils.session import ResettableSession


class AppChatImagineReverse:
    """Generate images through app-chat API instead of WebSocket."""

    @staticmethod
    async def generate(
        token: str,
        prompt: str,
        aspect_ratio: str = "1:1",
        n: int = 1,
        enable_nsfw: bool = False,
        stream: bool = False,
    ) -> AsyncGenerator[Dict[str, Any], None]:
        """
        Generate images using app-chat API.
        
        Args:
            token: Grok session token
            prompt: Image generation prompt
            aspect_ratio: Image aspect ratio (1:1, 2:3, 3:2, 9:16, 16:9)
            n: Number of images to generate (currently only 1 is supported via chat)
            enable_nsfw: Whether to enable NSFW content
            stream: Whether to stream responses
            
        Yields:
            Dict with type and data:
                - {"type": "image", "url": "...", "index": 0}
                - {"type": "progress", "message": "..."}
                - {"type": "error", "error": "...", "error_code": "..."}
        """
        browser = get_config("proxy.browser")
        session = ResettableSession(impersonate=browser)
        
        logger.info(
            f"AppChatImagine: Starting image generation via chat channel - "
            f"prompt='{prompt[:50]}...', ratio={aspect_ratio}, n={n}, nsfw={enable_nsfw}"
        )
        
        try:
            # Build the message for Grok
            # We use a special format that tells Grok to generate an image
            chat_message = f"Generate an image: {prompt}"
            if aspect_ratio and aspect_ratio != "1:1":
                chat_message += f" (aspect ratio: {aspect_ratio})"
            
            logger.debug(f"AppChatImagine: Sending chat message: {chat_message}")
            
            # Configure model to use grok-3 (which supports image generation)
            model_config_override = {
                "responseType": "imagine",  # Tell Grok we want image generation
                "aspectRatio": aspect_ratio,
            }
            
            # Request image generation through app-chat
            stream_response = await AppChatReverse.request(
                session,
                token,
                message=chat_message,
                model="grok-3",  # Use grok-3 for image generation
                mode="MODEL_MODE_FAST",
                file_attachments=None,
                tool_overrides=None,
                model_config_override=model_config_override,
            )
            
            logger.info("AppChatImagine: Chat connection established, processing response")
            
            # Process the streaming response
            image_count = 0
            message_buffer = ""
            seen_urls = set()
            
            async for line in stream_response:
                try:
                    # Parse SSE line
                    line = line.strip()
                    if not line:
                        continue
                    
                    logger.debug(f"AppChatImagine: Received line: {line[:100]}...")
                    
                    # Skip event type lines
                    if line.startswith("event:"):
                        continue
                    
                    # Parse data lines
                    if line.startswith("data:"):
                        data_str = line[5:].strip()
                        
                        # Skip [DONE] marker
                        if data_str == "[DONE]":
                            logger.debug("AppChatImagine: Received [DONE] marker")
                            continue
                        
                        # Try to parse as JSON
                        import orjson
                        try:
                            data = orjson.loads(data_str)
                        except Exception as e:
                            logger.warning(f"AppChatImagine: Failed to parse JSON: {e}")
                            continue
                        
                        # Check for errors
                        if isinstance(data, dict) and "error" in data:
                            error_msg = data.get("error", "Unknown error")
                            error_code = data.get("error_code", "unknown_error")
                            logger.error(f"AppChatImagine: Error from chat API: {error_msg}")
                            yield {
                                "type": "error",
                                "error": error_msg,
                                "error_code": error_code,
                            }
                            return
                        
                        # Extract message content
                        message_content = None
                        if isinstance(data, dict):
                            # Try different response formats
                            if "response" in data:
                                message_content = data["response"]
                            elif "message" in data:
                                message_content = data["message"]
                            elif "content" in data:
                                message_content = data["content"]
                            elif "choices" in data and len(data["choices"]) > 0:
                                delta = data["choices"][0].get("delta", {})
                                message_content = delta.get("content", "")
                        
                        if message_content:
                            message_buffer += str(message_content)
                            logger.debug(f"AppChatImagine: Accumulated message length: {len(message_buffer)}")
                            
                            # Look for image URLs in the message
                            # Grok typically returns URLs in markdown format: ![](url)
                            # or direct URLs
                            urls = self._extract_image_urls(message_buffer)
                            
                            for url in urls:
                                if url not in seen_urls:
                                    seen_urls.add(url)
                                    logger.info(f"AppChatImagine: Found image URL #{image_count + 1}: {url}")
                                    
                                    yield {
                                        "type": "image",
                                        "url": url,
                                        "index": image_count,
                                    }
                                    image_count += 1
                                    
                                    if image_count >= n:
                                        logger.info(f"AppChatImagine: Received {image_count}/{n} images, stopping")
                                        return
                        
                        # Emit progress for streaming
                        if stream and message_content:
                            yield {
                                "type": "progress",
                                "message": message_content,
                            }
                
                except Exception as e:
                    logger.warning(f"AppChatImagine: Error processing line: {e}")
                    continue
            
            logger.info(f"AppChatImagine: Stream completed, generated {image_count} images")
            
            # If we didn't find any images, check the final message buffer
            if image_count == 0 and message_buffer:
                logger.warning(
                    f"AppChatImagine: No images found in response. "
                    f"Message buffer: {message_buffer[:200]}..."
                )
                yield {
                    "type": "error",
                    "error": "No images found in chat response",
                    "error_code": "no_images_generated",
                }
        
        except Exception as e:
            logger.error(f"AppChatImagine: Generation failed: {e}", exc_info=True)
            yield {
                "type": "error",
                "error": str(e),
                "error_code": "generation_failed",
            }
        
        finally:
            try:
                await session.close()
                logger.debug("AppChatImagine: Session closed")
            except Exception:
                pass
    
    @staticmethod
    def _extract_image_urls(text: str) -> List[str]:
        """Extract image URLs from text."""
        urls = []
        
        # Pattern 1: Markdown image syntax ![alt](url)
        markdown_pattern = r'!\[.*?\]\((https?://[^\s\)]+)\)'
        urls.extend(re.findall(markdown_pattern, text))
        
        # Pattern 2: Direct Grok CDN URLs
        grok_cdn_pattern = r'(https://[^\s]*grok[^\s]*\.(?:jpg|jpeg|png|webp|gif))'
        urls.extend(re.findall(grok_cdn_pattern, text, re.IGNORECASE))
        
        # Pattern 3: Any image URL
        image_url_pattern = r'(https?://[^\s]+\.(?:jpg|jpeg|png|webp|gif))'
        urls.extend(re.findall(image_url_pattern, text, re.IGNORECASE))
        
        # Pattern 4: Grok generated URLs (specific pattern)
        grok_generated_pattern = r'(https://[^\s]*/generated/[^\s]+)'
        urls.extend(re.findall(grok_generated_pattern, text))
        
        # Remove duplicates while preserving order
        seen = set()
        unique_urls = []
        for url in urls:
            if url not in seen:
                seen.add(url)
                unique_urls.append(url)
        
        return unique_urls
